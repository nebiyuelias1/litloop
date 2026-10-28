require "tomlrb"

namespace :theme do
  desc "Generate web/Android/iOS theme files from the root theme.toml and icons/"
  task :generate do
    backend_root = File.expand_path("../..", __dir__)
    repo_root = File.expand_path("..", backend_root)
    tokens = Tomlrb.load_file(File.join(repo_root, "theme.toml"))

    abort("theme.toml: [dark] is not wired up yet — only [light] is supported.") if tokens.key?("dark")

    colors = tokens.fetch("light")
    header = "GENERATED from theme.toml by `bundle exec rake theme:generate` — do not edit."

    rgba = colors.transform_values { |hex| parse_hex(hex) }

    write_web_theme(repo_root, header, colors)
    write_android_colors(backend_root, header, rgba)
    write_ios_colorsets(backend_root, rgba)

    icons = Dir[File.join(repo_root, "icons", "*.svg")].sort
    write_web_icon_partials(backend_root, icons)
    write_android_icon_drawables(backend_root, icons)
    write_ios_icon_imagesets(backend_root, icons)

    puts "Generated theme files for web, Android, and iOS from theme.toml and icons/"
  end

  def parse_icon(svg_path)
    svg = File.read(svg_path)
    viewbox = svg[/viewBox="([^"]+)"/, 1]
    abort("icons/#{File.basename(svg_path)}: missing viewBox") unless viewbox

    min_x, min_y, width, height = viewbox.split(/\s+/)
    if min_x.to_f != 0 || min_y.to_f != 0
      abort("icons/#{File.basename(svg_path)}: non-zero viewBox origin (#{min_x}, #{min_y}) is not supported")
    end

    is_outline = svg.include?('fill="none"') || svg.include?('stroke="currentColor"')
    stroke_width = svg[/stroke-width="([^"]+)"/, 1] || "1.5"

    paths = svg.scan(/<path\b([^>]*)>/).map do |(attrs)|
      {
        d: attrs[/\bd="([^"]*)"/, 1],
        fill_rule: attrs[/\bfill-rule="([^"]*)"/, 1]
      }
    end.compact
    abort("icons/#{File.basename(svg_path)}: no <path> elements found") if paths.empty?

    { width: width, height: height, paths: paths, is_outline: is_outline, stroke_width: stroke_width }
  end

  def write_web_icon_partials(backend_root, icons)
    partials_dir = File.join(backend_root, "app/views/shared/icons")
    FileUtils.rm_rf(partials_dir)
    FileUtils.mkdir_p(partials_dir)
    return if icons.empty?

    icons.each do |icon|
      name = File.basename(icon, ".svg").tr("-", "_")
      svg = File.read(icon)
      svg = svg.sub("<svg ", "<svg class=\"<%= local_assigns[:classes] %>\" ")
      svg = svg.gsub('"/>', '" />') # satisfy erb_lint's self-closing-tag spacing
      File.write(File.join(partials_dir, "_#{name}.html.erb"), svg)
    end
  end

  def write_android_icon_drawables(backend_root, icons)
    drawable_dir = File.join(backend_root, "../android/app/src/main/res/drawable")
    FileUtils.mkdir_p(drawable_dir)
    Dir[File.join(drawable_dir, "ic_*.xml")].each do |path|
      FileUtils.rm(path) if File.read(path).include?("GENERATED from icons/")
    end
    return if icons.empty?

    icons.each do |icon|
      name = File.basename(icon, ".svg").tr("-", "_")
      icon_data = parse_icon(icon)

      xml = +<<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <!-- GENERATED from icons/#{File.basename(icon)} by `bundle exec rake theme:generate` — do not edit. -->
        <vector xmlns:android="http://schemas.android.com/apk/res/android"
            android:width="#{icon_data[:width]}dp"
            android:height="#{icon_data[:height]}dp"
            android:viewportWidth="#{icon_data[:width]}"
            android:viewportHeight="#{icon_data[:height]}">
      XML
      icon_data[:paths].each do |path|
        if icon_data[:is_outline]
          xml << "    <path\n"
          xml << "        android:strokeColor=\"#FF000000\"\n"
          xml << "        android:strokeWidth=\"#{icon_data[:stroke_width]}\"\n"
          xml << "        android:strokeLineCap=\"round\"\n"
          xml << "        android:strokeLineJoin=\"round\"\n"
          xml << "        android:pathData=\"#{path[:d]}\" />\n"
        else
          xml << "    <path\n        android:fillColor=\"#FF000000\"\n"
          xml << "        android:fillType=\"evenOdd\"\n" if path[:fill_rule] == "evenodd"
          xml << "        android:pathData=\"#{path[:d]}\" />\n"
        end
      end
      xml << "</vector>\n"

      File.write(File.join(drawable_dir, "ic_#{name}.xml"), xml)
    end

    # Generate state-list tab selectors for icons that have a corresponding _solid variant
    clean_names = icons.map { |i| File.basename(i, ".svg").tr("-", "_") }
    clean_names.grep(/_solid\z/).each do |solid_name|
      base_name = solid_name.sub(/_solid\z/, "")
      next unless clean_names.include?(base_name)

      selector_xml = +<<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <!-- GENERATED from icons/#{base_name}.svg and icons/#{solid_name}.svg by `bundle exec rake theme:generate` — do not edit. -->
        <selector xmlns:android="http://schemas.android.com/apk/res/android">
            <item android:state_checked="true" android:drawable="@drawable/ic_#{solid_name}" />
            <item android:drawable="@drawable/ic_#{base_name}" />
        </selector>
      XML
      File.write(File.join(drawable_dir, "ic_tab_#{base_name}.xml"), selector_xml)
    end
  end

  def write_ios_icon_imagesets(backend_root, icons)
    icons_dir = File.join(backend_root, "../ios/App/Resources/Assets.xcassets/Icons")
    FileUtils.rm_rf(icons_dir)
    FileUtils.mkdir_p(icons_dir)

    folder_json = { info: { author: "xcode", version: 1 }, properties: { "provides-namespace": true } }
    File.write(File.join(icons_dir, "Contents.json"), JSON.pretty_generate(folder_json) << "\n")
    return if icons.empty?

    icons.each do |icon|
      name = File.basename(icon, ".svg").tr("-", "_").split("_").map(&:capitalize).join
      imageset = File.join(icons_dir, "#{name}.imageset")
      FileUtils.mkdir_p(imageset)
      FileUtils.cp(icon, File.join(imageset, "icon.svg"))

      json = {
        images: [ { filename: "icon.svg", idiom: "universal" } ],
        info: { author: "xcode", version: 1 },
        properties: {
          "preserves-vector-representation": true,
          "template-rendering-intent": "template"
        }
      }
      File.write(File.join(imageset, "Contents.json"), JSON.pretty_generate(json) << "\n")
    end
  end

  def parse_hex(hex)
    h = hex.delete("#").downcase
    h = h.chars.map { |c| c * 2 }.join if h.length == 3
    h = "ff#{h}" if h.length == 6
    abort("theme.toml: invalid hex color \"#{hex}\"") unless h.match?(/\A[0-9a-f]{8}\z/)

    h.to_i(16)
  end

  def write_web_theme(repo_root, header, colors)
    css = +<<~CSS
      /* #{header} */
      @theme {
    CSS
    colors.each { |name, hex| css << "  --color-#{name.tr('_', '-')}: #{hex};\n" }
    css << "}\n"

    # DaisyUI themes (e.g. the pinned data-theme="silk") redeclare --color-primary and
    # --color-accent on [data-theme=...], which out-cascades the bare :root @theme block.
    # Re-declare every brand token at higher specificity so theme.toml stays the single
    # source of truth regardless of which DaisyUI theme is active.
    css << "\n/* Brand tokens win over DaisyUI data-theme overrides. */\n"
    css << ":root,\n:root[data-theme] {\n"
    colors.each { |name, hex| css << "  --color-#{name.tr('_', '-')}: #{hex};\n" }
    css << "}\n"

    path = File.join(repo_root, "backend/app/assets/tailwind/theme.css")
    File.write(path, css)
  end

  def write_android_colors(backend_root, header, rgba)
    xml = +<<~XML
      <?xml version="1.0" encoding="utf-8"?>
      <!-- #{header} -->
      <resources>
    XML
    rgba.each { |name, value| xml << format("    <color name=\"%s\">#%08X</color>\n", name, value) }
    xml << "</resources>\n"

    path = File.join(backend_root, "../android/app/src/main/res/values/colors.xml")
    File.write(path, xml)
  end

  def write_ios_colorsets(backend_root, rgba)
    colors_dir = File.join(backend_root, "../ios/App/Resources/Assets.xcassets/Colors")
    FileUtils.rm_rf(colors_dir)

    rgba.each do |name, value|
      colorset = File.join(colors_dir, "#{name.split('_').map(&:capitalize).join}.colorset")
      write_colorset(colorset, value)
    end

    # Fill the empty template AccentColor slot with the brand primary.
    write_colorset(
      File.join(backend_root, "../ios/App/Resources/Assets.xcassets/AccentColor.colorset"),
      rgba.fetch("primary")
    )
  end

  def write_colorset(path, value)
    alpha = ((value >> 24) & 0xff) / 255.0
    red = ((value >> 16) & 0xff) / 255.0
    green = ((value >> 8) & 0xff) / 255.0
    blue = (value & 0xff) / 255.0

    json = {
      colors: [ {
        color: {
          "color-space": "srgb",
          components: {
            alpha: format("%.3f", alpha),
            blue: format("%.3f", blue),
            green: format("%.3f", green),
            red: format("%.3f", red)
          }
        },
        idiom: "universal"
      } ],
      info: { author: "xcode", version: 1 }
    }

    FileUtils.mkdir_p(path)
    File.write(File.join(path, "Contents.json"), JSON.pretty_generate(json) << "\n")
  end
end
