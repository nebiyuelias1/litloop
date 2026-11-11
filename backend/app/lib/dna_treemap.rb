# frozen_string_literal: true

# Squarified treemap layout (Bruls, Huizing & van Wijk) for the Literature
# DNA theme composition panel. Pure geometry: items in, rectangles out —
# no rendering, no AI, deterministic given the same input order.
#
#   DnaTreemap.squarify([["war", 9], ["memory", 4]], width: 100, height: 60)
#   => [{"label"=>"war", "value"=>9.0, "x"=>0.0, "y"=>0.0, "w"=>66.67, "h"=>60.0}, ...]
#
# Convention (as in the paper): a wide rectangle (w >= h) grows a vertical
# column against its left edge; a tall rectangle grows a horizontal row
# against its top edge. Items keep growing the row while the worst aspect
# ratio improves, then the row is fixed and the remainder recurses.
module DnaTreemap
  MIN_RECT = 0.0001

  module_function

  # Returns rectangles covering width x height. Values are scaled so their
  # areas sum to exactly width*height; the raw value is kept for labels.
  # Input is sorted descending by value first (the algorithm's precondition)
  # so the call site can pass any order.
  def squarify(items, width:, height:)
    items = items.reject { |_, value| value.to_f <= 0 }
    return [] if items.empty? || width <= 0 || height <= 0

    total = items.sum { |_, value| value.to_f }
    scale = (width.to_f * height.to_f) / total
    ordered = items.sort_by { |_, value| -value.to_f }
      .map { |label, value| { label: label.to_s, value: value.to_f, area: value.to_f * scale } }

    rects = []
    layout(ordered, x: 0.0, y: 0.0, w: width.to_f, h: height.to_f, rects: rects)
    rects
  end

  def layout(items, x:, y:, w:, h:, rects:)
    return if items.empty?

    if items.size == 1
      rects << rect(items.first, x: x, y: y, w: w, h: h)
      return
    end

    vertical = w >= h
    edge = vertical ? h : w
    row = []
    row_area = 0.0
    best = nil

    items.each do |item|
      candidate = worst_ratio(row + [ item ], row_area + item[:area], edge, vertical, w, h)
      break if best && candidate > best

      row << item
      row_area += item[:area]
      best = candidate
    end

    if vertical
      thickness = row_area / h
      offset = 0.0
      row.each do |item|
        length = h * item[:area] / row_area
        rects << rect(item, x: x, y: y + offset, w: thickness, h: length)
        offset += length
      end
      layout(items.drop(row.size), x: x + thickness, y: y, w: w - thickness, h: h, rects: rects)
    else
      thickness = row_area / w
      offset = 0.0
      row.each do |item|
        length = w * item[:area] / row_area
        rects << rect(item, x: x + offset, y: y, w: length, h: thickness)
        offset += length
      end
      layout(items.drop(row.size), x: x, y: y + thickness, w: w, h: h - thickness, rects: rects)
    end
  end

  def worst_ratio(row, row_area, edge, vertical, w, h)
    thickness = vertical ? row_area / h : row_area / w
    return Float::INFINITY if thickness <= MIN_RECT

    row.map do |item|
      length = edge * item[:area] / row_area
      next Float::INFINITY if length <= MIN_RECT

      [ length, thickness ].max / [ length, thickness ].min
    end.max
  end

  def rect(item, x:, y:, w:, h:)
    { "label" => item[:label], "value" => item[:value],
      "x" => x, "y" => y, "w" => w, "h" => h }
  end
end
