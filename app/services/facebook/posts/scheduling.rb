# frozen_string_literal: true

module Facebook
  module Posts
    # Mọi phép đổi giờ địa phương ↔ UTC nằm ở đây. scheduled_at trong DB luôn là
    # UTC; timezone lưu riêng để hiển thị lại đúng giờ người dùng đã chọn.
    module Scheduling
      module_function

      # "2026-10-30T09:00" + "Asia/Ho_Chi_Minh" → Time (UTC). Input đã là Time thì giữ.
      def parse_local(value, timezone)
        zone = ActiveSupport::TimeZone[timezone.to_s] or raise ArgumentError, "Múi giờ không hợp lệ: #{timezone}"
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)

        zone.parse(value.to_s) or raise ArgumentError, "Thời điểm không hợp lệ: #{value}"
      end

      def enqueue(post)
        FacebookPublishJob.set(wait_until: post.effective_run_at).perform_later(post.id, post.schedule_token)
      end
    end
  end
end
