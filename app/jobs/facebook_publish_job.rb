# Đăng một bài đã lên lịch. Chạy nền (Solid Queue trên production — bền qua
# restart, không phụ thuộc trình duyệt). Idempotent: Publish tự khoá + kiểm tra
# token lịch, chạy trùng chỉ no-op.
class FacebookPublishJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(post_id, schedule_token = nil)
    post = FacebookPost.find_by(id: post_id)
    return if post.nil?

    result = Facebook::Posts::Publish.call(post: post, schedule_token: schedule_token)
    # Chưa tới giờ (job chạy sớm do đồng hồ lệch) → đặt lại đúng giờ.
    Facebook::Posts::Scheduling.enqueue(post.reload) if result.outcome == :not_due
  end
end
