# frozen_string_literal: true

module FacebookGroupsHelper
  SHARE_STATUS_CSS = {
    "pending" => "pill-amber", "posted" => "pill-teal", "rejected" => "pill-rose", "skipped" => "pill-gray"
  }.freeze

  def group_share_status_pill(share)
    key = share.overdue? ? "overdue" : share.status
    css = share.overdue? ? "pill-rose" : SHARE_STATUS_CSS.fetch(share.status, "pill")
    tag.span(class: "pill #{css}") { tag.span(class: "pdot") + t("marketingos.facebook_groups.share.status.#{key}") }
  end

  def group_share_time(share)
    I18n.l(share.scheduled_local, format: :datetime_short)
  end

  # Giá trị cho <input type="datetime-local"> theo múi giờ của bài.
  def group_share_time_input(time, timezone)
    time.in_time_zone(timezone).strftime("%Y-%m-%dT%H:%M")
  end

  def group_tag_pills(group)
    safe_join(group.tag_list.map { |t| tag.span(t, class: "pill pill-gray gs-tag") }, " ")
  end
end
