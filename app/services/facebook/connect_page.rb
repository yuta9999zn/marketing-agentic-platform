# frozen_string_literal: true

module Facebook
  # Chọn Page từ FacebookAuthorization → tạo/cập nhật FacebookPageConnection.
  # Token Page được chuyển thẳng từ bản mã hoá tạm sang bản mã hoá lâu dài.
  class ConnectPage
    def self.call(authorization:, page_id:, user:)
      raise Facebook::StateError, "Phiên uỷ quyền đã hết hạn — hãy kết nối lại." unless authorization.active?

      page = authorization.pages.find { |p| p["id"].to_s == page_id.to_s }
      raise Facebook::StateError, "Page không nằm trong danh sách bạn quản lý." if page.nil?

      token = authorization.page_token(page_id)
      raise Facebook::StateError, "Không nhận được token cho Page này." if token.blank?

      org = authorization.organization
      conn = FacebookPageConnection.find_or_initialize_by(organization: org, page_id: page["id"].to_s)
      conn.assign_attributes(
        connected_by: user, page_name: page["name"], page_category: page["category"],
        page_link: page["link"], page_username: page["username"], picture_url: page["picture_url"],
        granted_scopes: authorization.granted_scopes, page_tasks: Array(page["tasks"]),
        token_expires_at: authorization.token_expires_at, status: "connected",
        last_error: nil, last_error_code: nil, disconnected_at: nil,
        connection_mode: authorization.mode, last_checked_at: Time.current
      )
      conn.access_token = token
      conn.save!
      authorization.update!(consumed_at: Time.current)
      authorization.destroy # không giữ token tạm lâu hơn cần thiết

      # Thiếu quyền/vai trò → báo ngay, nhưng vẫn lưu kết nối để người dùng thấy chẩn đoán.
      conn.refresh_status_from_scopes!
      AuditLog.record!(org: org, user: user, action: "facebook.page.connected", subject: conn,
                       details: { "page_id" => conn.page_id, "page_name" => conn.page_name,
                                  "mode" => conn.connection_mode, "scopes" => conn.granted_scopes })
      conn
    end
  end
end
