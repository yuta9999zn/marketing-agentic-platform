# AI viết biến thể nội dung cho từng nhóm ở nền (model thật mất 20-90 giây).
class FacebookGroupVariantsJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(share_ids:, user_id:)
    user = User.find_by(id: user_id)
    shares = FacebookGroupShare.where(id: share_ids).includes(:facebook_group, facebook_post: :facebook_page_connection).order(:scheduled_at, :id).to_a
    return if user.nil? || shares.empty?

    post = shares.first.facebook_post
    updated = Ai::Workflows::FacebookGroupVariants.call(shares: shares, user: user)
    Notifications::Builder.notify(user: user, org: post.organization, kind: "facebook_group_variants_ready",
                                  payload: { "title" => post.title.presence || post.message.to_s.truncate(60),
                                             "count" => updated.size.to_s })
  rescue StandardError => e
    Rails.logger.error("FacebookGroupVariantsJob thất bại: #{e.class}: #{e.message}")
    if user && post
      Notifications::Builder.notify(user: user, org: post.organization, kind: "facebook_group_variants_failed",
                                    payload: { "error" => e.message.to_s.truncate(200) })
    end
  end
end
