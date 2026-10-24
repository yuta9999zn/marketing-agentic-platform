# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  INTERNAL_ROLES = %w[owner admin manager strategist copywriter designer
                      project_manager approver].freeze
  CAMPAIGN_SCOPED_ROLES = %w[client external_reviewer].freeze

  included do
    helper_method :current_user, :current_organization, :current_role, :logged_in?, :policy_for, :campaign_scoped_role?
    before_action :require_login
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  # CHỈ resolve org qua membership của user. Session org_id không hợp lệ
  # (membership bị thu hồi) → xoá khỏi session, fallback org đầu tiên còn hợp lệ.
  # Không bao giờ trả Organization từ global ID.
  def current_organization
    return @current_organization if defined?(@current_organization)

    @current_organization = nil
    if current_user
      if session[:org_id]
        org = current_user.organizations.find_by(id: session[:org_id])
        if org.nil?
          session.delete(:org_id) # membership đã bị thu hồi — đừng tin session cũ
        else
          @current_organization = org
        end
      end
      @current_organization ||= current_user.organizations.first
    end
    @current_organization
  end

  def current_role
    current_user&.role_in(current_organization) if current_organization
  end

  def logged_in? = current_user.present?

  # Fail-closed ở hai tầng: chưa đăng nhập HOẶC không còn membership tổ chức nào.
  def require_login
    if logged_in? && current_organization.present?
      return
    end

    reset_session
    redirect_to login_path, alert: "Phiên làm việc không còn hợp lệ. Vui lòng đăng nhập lại."
  end

  # Fail-closed: trả về true/false. Caller PHẢI dùng `return unless require_role!(...)`
  # để action dừng hẳn sau khi redirect — không ghi dữ liệu, không render tiếp.
  def require_role!(permission, subject: nil)
    return true if policy_for(subject).allowed?(permission)

    redirect_to root_path, alert: "Bạn không có quyền thực hiện thao tác này."
    false
  end

  def policy_for(subject = nil)
    Policy.new(user: current_user, org: current_organization, role: current_role, subject: subject)
  end

  # Khu vực nội bộ: CHỈ role trong INTERNAL_ROLES allowlist. Role blank,
  # client, external_reviewer đều bị chặn — kể cả qua URL trực tiếp.
  def require_internal!
    return true if INTERNAL_ROLES.include?(current_role.to_s)

    redirect_to root_path, alert: "Khu vực này chỉ dành cho đội nội bộ."
    false
  end

  def campaign_scoped_role? = CAMPAIGN_SCOPED_ROLES.include?(current_role.to_s)
end
