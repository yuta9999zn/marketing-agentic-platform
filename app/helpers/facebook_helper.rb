# frozen_string_literal: true

module FacebookHelper
  POST_STATUS_CSS = {
    "draft" => "pill-gray", "pending_approval" => "pill-amber", "approved" => "pill-violet",
    "scheduled" => "pill", "publishing" => "pill", "published" => "pill-teal",
    "failed" => "pill-rose", "cancelled" => "pill-gray"
  }.freeze

  CONNECTION_STATUS_CSS = {
    "connected" => "pill-teal", "token_expired" => "pill-rose", "permission_missing" => "pill-rose",
    "error" => "pill-rose", "disconnected" => "pill-gray"
  }.freeze

  def fb_post_status_pill(post)
    label = t("marketingos.facebook.post_status.#{post.status}", default: post.status.humanize)
    label = t("marketingos.facebook.post_status.retrying", attempt: post.attempts, max: post.max_attempts) if post.retrying?
    tag.span(class: "pill #{POST_STATUS_CSS.fetch(post.status, 'pill')}") { tag.span(class: "pdot") + label }
  end

  def fb_connection_status_pill(conn)
    label = t("marketingos.facebook.connection_status.#{conn.status}", default: conn.status.humanize)
    tag.span(class: "pill #{CONNECTION_STATUS_CSS.fetch(conn.status, 'pill')}") { tag.span(class: "pdot") + label }
  end

  def fb_issue_text(issue)
    t("marketingos.facebook.issues.#{issue.code}", **(issue.params || {}).transform_values(&:to_s), default: issue.code.to_s.humanize)
  end

  def fb_issue_fix(issue)
    t("marketingos.facebook.issue_fix.#{issue.code}", default: "")
  end

  def fb_error_label(code)
    return "" if code.blank?

    t("marketingos.facebook.issues.#{code}", default: code.to_s.humanize)
  end

  def fb_local_time(post)
    return "" if post.scheduled_at.blank?

    "#{I18n.l(post.scheduled_local, format: :datetime_short)} (#{post.timezone})"
  end

  def fb_mode_badge
    mode = Facebook::Config.mode
    css = { mock: "ai-fake", live: "ai-ready", unconfigured: "ai-down" }[mode]
    tag.span(class: "ai-status #{css}") { tag.span(class: "pdot") + t("marketingos.facebook.mode.#{mode}") }
  end

  # Xem trước bài như trên Facebook — chỉ hiển thị, không gọi mạng.
  def fb_preview_message(message)
    safe_join(message.to_s.split(/\n/).map { |line| line =~ /\A\s*\z/ ? "".html_safe : tag.span(auto_hashtags(line)) }, tag.br)
  end

  def auto_hashtags(line)
    safe_join(line.split(/(\s+)/).map { |w| w.start_with?("#") && w.length > 1 ? tag.span(w, class: "fb-hashtag") : w })
  end
end
