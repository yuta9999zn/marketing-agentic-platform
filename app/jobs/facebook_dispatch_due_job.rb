# Lưới an toàn chạy định kỳ (recurring.yml / cron): đẩy mọi bài đã tới giờ mà
# job delay bị mất (restart, deploy) và xử lý bài kẹt ở `publishing`.
class FacebookDispatchDueJob < ApplicationJob
  queue_as :default

  def perform
    FacebookPost.due.find_each do |post|
      FacebookPublishJob.perform_later(post.id, post.schedule_token)
    end

    FacebookPost.where(status: "publishing")
                .where("publish_started_at < ?", Facebook::Posts::Publish::STUCK_AFTER.ago)
                .find_each { |post| Facebook::Posts::Reconcile.call(post: post) }
  end
end
