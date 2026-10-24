# frozen_string_literal: true

# Biểu đồ SVG thuần (không thư viện ngoài). Màu lấy từ token hệ thống:
# indigo-600 (#4F46E5) và teal-600 (#0FAD9A) — hai màu đã kiểm tra tách biệt
# với người mù màu. Số luôn đi kèm nhãn chữ, không chỉ màu.
module DashboardHelper
  SERIES_COLORS = { created: "#4F46E5", published: "#0FAD9A" }.freeze

  def delta_pill(current, previous)
    return tag.span("—", class: "kpi-delta kpi-flat") if previous.to_i.zero? && current.to_i.zero?
    return tag.span("+#{current}", class: "kpi-delta kpi-up") if previous.to_i.zero?

    pct = (((current - previous).to_f / previous) * 100).round
    css = pct.positive? ? "kpi-up" : (pct.negative? ? "kpi-down" : "kpi-flat")
    arrow = pct.positive? ? "↑" : (pct.negative? ? "↓" : "→")
    tag.span("#{arrow} #{pct.abs}%", class: "kpi-delta #{css}")
  end

  # Sparkline 7-30 điểm, 1 series.
  def sparkline_svg(values, color:, width: 160, height: 30)
    values = Array(values).map(&:to_f)
    return "".html_safe if values.size < 2

    max = [ values.max, 1 ].max
    step = width.to_f / (values.size - 1)
    pts = values.each_with_index.map { |v, i| [ (i * step).round(1), (height - 3 - (v / max) * (height - 6)).round(1) ] }
    line = pts.map { |x, y| "#{x},#{y}" }.join(" ")
    area = "0,#{height} #{line} #{width},#{height}"
    tag.svg(viewBox: "0 0 #{width} #{height}", width: width, height: height, class: "sparkline", "aria-hidden": true) do
      tag.polygon(points: area, fill: color, opacity: 0.12) +
        tag.polyline(points: line, fill: "none", stroke: color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round")
    end
  end

  # Biểu đồ đường 2 series với tooltip hover (Stimulus `chart`), legend + bảng dữ liệu ẩn cho screen reader.
  def line_chart_svg(days:, series:, width: 760, height: 220)
    pad_l, pad_r, pad_t, pad_b = 36, 12, 12, 26
    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    all = series.values.flatten.map(&:to_f)
    max = [ all.max || 0, 4 ].max
    nice_max = ((max / 4.0).ceil * 4)
    n = days.size
    step = n > 1 ? plot_w.to_f / (n - 1) : plot_w
    x_at = ->(i) { (pad_l + i * step).round(1) }
    y_at = ->(v) { (pad_t + plot_h - (v.to_f / nice_max) * plot_h).round(1) }

    grid = (0..4).map do |g|
      y = (pad_t + plot_h - g * plot_h / 4.0).round(1)
      tag.line(x1: pad_l, x2: width - pad_r, y1: y, y2: y, stroke: "#E6E9F2", "stroke-width": 1) +
        tag.text((nice_max * g / 4).to_i.to_s, x: pad_l - 8, y: y + 4, "text-anchor": "end", class: "chart-axis")
    end
    labels = days.each_with_index.select { |_, i| i % 5 == 0 || i == n - 1 }.map do |d, i|
      tag.text(d.strftime("%d/%m"), x: x_at.(i), y: height - 6, "text-anchor": "middle", class: "chart-axis")
    end
    lines = series.map do |key, values|
      color = SERIES_COLORS.fetch(key)
      pts = values.each_with_index.map { |v, i| "#{x_at.(i)},#{y_at.(v)}" }.join(" ")
      tag.polyline(points: pts, fill: "none", stroke: color, "stroke-width": 2.2, "stroke-linejoin": "round", "stroke-linecap": "round")
    end
    hit = days.each_with_index.map do |d, i|
      x = x_at.(i)
      tag.g(class: "chart-col", data: { chart_target: "col", date: d.strftime("%d/%m"),
                                        values: series.map { |k, v| "#{t("marketingos.dashboard.series.#{k}")}: #{v[i]}" }.join(" · ") }) do
        tag.rect(x: x - step / 2, y: pad_t, width: [ step, 1 ].max, height: plot_h, fill: "transparent") +
          safe_join(series.map { |key, values| tag.circle(cx: x, cy: y_at.(values[i]), r: 4, fill: SERIES_COLORS.fetch(key), stroke: "#fff", "stroke-width": 1.5, class: "chart-dot") })
      end
    end
    tag.svg(viewBox: "0 0 #{width} #{height}", width: "100%", class: "line-chart", role: "img",
            "aria-label": t("marketingos.dashboard.chart_aria", days: n), preserveAspectRatio: "none") do
      safe_join(grid) + safe_join(labels) + safe_join(lines) + safe_join(hit)
    end
  end
end
