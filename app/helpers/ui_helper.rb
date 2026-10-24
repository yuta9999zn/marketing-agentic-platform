# frozen_string_literal: true

module UiHelper
  ICONS = {
    "home" => '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h5v-6h4v6h5V9.5"/>',
    "folder" => '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/>',
    "pen" => '<path d="m14 4 6 6-9.5 9.5H4v-6.5L14 4Z"/><path d="m12 6 6 6"/>',
    "calendar" => '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M8 3v4M16 3v4M3 10h18"/>',
    "briefcase" => '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2"/>',
    "layers" => '<path d="m12 3 9 5-9 5-9-5 9-5Z"/><path d="m3 13 9 5 9-5"/>',
    "settings" => '<circle cx="12" cy="12" r="3"/><path d="M12 2v3m0 14v3M4.9 4.9l2.1 2.1m10 10 2.1 2.1M2 12h3m14 0h3M4.9 19.1 7 17m10-10 2.1-2.1"/>',
    "search" => '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    "bell" => '<path d="M6 9a6 6 0 1 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z"/><path d="M10 20a2 2 0 0 0 4 0"/>',
    "check" => '<path d="m4.5 12.5 5 5 10-11"/>',
    "plus" => '<path d="M12 5v14M5 12h14"/>',
    "spark" => '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z"/>',
    "alert" => '<path d="M12 4 2.5 20h19L12 4Z"/><path d="M12 10v4m0 3v.5"/>',
    "clock" => '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/>',
    "users" => '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.2 3.4-5 6.5-5s5.7 1.8 6.5 5"/><circle cx="17.5" cy="9" r="2.5"/><path d="M16 15.2c2.4.3 4.3 1.9 5 4.8"/>',
    "doc" => '<path d="M6 3h8l4 4v14H6V3Z"/><path d="M14 3v4h4"/>',
    "video" => '<rect x="3" y="6" width="13" height="12" rx="2"/><path d="m16 10 5-3v10l-5-3"/>',
    "chart" => '<path d="M4 20V10m6 10V4m6 16v-7"/>',
    "x" => '<path d="M6 6l12 12M18 6 6 18"/>',
    "menu" => '<path d="M4 6h16M4 12h16M4 18h16"/>',
    "chev-r" => '<path d="m9 5 7 7-7 7"/>'
  }.freeze

  def icon(name, label: nil, size: 20)
    path = ICONS.fetch(name) { '<circle cx="12" cy="12" r="9"/>' }
    tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
            "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round",
            width: size, height: size, role: label ? "img" : nil,
            "aria-label": label, "aria-hidden": label ? nil : true) { path.html_safe }
  end

  def initials(name)
    name.to_s.split(/\s+/).map { |w| w[0] }.reject { |c| c =~ /\p{^Alnum}/ }.first(2).join.upcase.presence || "?"
  end

  def avatar(name, lg: false, navy: false)
    tag.span(initials(name), class: ["avatar", ("avatar-lg" if lg), ("avatar-navy" if navy)].compact,
             title: name, "aria-label": name)
  end

  def fmt_date(date)
    return "" if date.blank?
    I18n.l(date.to_date, format: :short)
  end

  def fmt_datetime(dt)
    return "" if dt.blank?
    I18n.l(dt.in_time_zone, format: :datetime_short)
  end

  # Nhãn trạng thái AI — nói đúng đang chạy bằng gì, kể cả khi hỏng.
  # Không bao giờ raise: Availability đã nuốt mọi lỗi mạng.
  def ai_status_badge
    st = Ai::Availability.status
    css, label =
      if st.fake?
        ["ai-fake", t("marketingos.ai_status.fake")]
      elsif !st.ready?
        ["ai-down", t("marketingos.ai_status.#{st.detail}", default: t("marketingos.ai_status.unreachable"))]
      elsif st.local?
        ["ai-ready", t("marketingos.ai_status.local", model: st.model)]
      else
        ["ai-ready", t("marketingos.ai_status.external", provider: st.provider)]
      end
    tag.span(class: "ai-status #{css}", title: label) do
      tag.span(class: "pdot") + label
    end
  end
end
