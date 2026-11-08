module BooksHelper
  # "NG" -> "🇳🇬 Nigeria"
  def country_display(code)
    return nil if code.blank?

    name = CountryCodes.name_for(code)
    flag = CountryCodes.flag_for(code)
    [ flag, name ].compact.join(" ")
  end
end
