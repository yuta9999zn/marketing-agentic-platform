# frozen_string_literal: true

module Facebook
  module Posts
    # Ghi audit + notification cho mọi thay đổi trạng thái bài đăng.
    module Audit
      module_function

      def record(post, action, user: nil, details: {})
        AuditLog.record!(org: post.organization, user: user, action: "facebook.post.#{action}", subject: post,
                         details: { "status" => post.status, "page_id" => post.facebook_page_connection.page_id }.merge(details))
      end

      def notify(post, kind, user:, payload: {})
        Notifications::Builder.notify(user: user, org: post.organization, kind: kind,
                                      payload: { "facebook_post_id" => post.id, "title" => post.title.presence || post.message.to_s.truncate(60) }.merge(payload))
      end

      def notify_approvers(post, kind, except_user: nil)
        Notifications::Builder.notify_role(org: post.organization, roles: %w[owner admin manager approver],
                                           kind: kind, except_user: except_user,
                                           payload: { "facebook_post_id" => post.id, "title" => post.title.presence || post.message.to_s.truncate(60) })
      end
    end
  end
end
