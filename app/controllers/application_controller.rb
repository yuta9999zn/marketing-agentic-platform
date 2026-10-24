class ApplicationController < ActionController::Base
  include Authentication
  # Multi-tenant: mọi truy vấn nghiệp vụ phải scope theo current_organization.
  rescue_from ActiveRecord::RecordNotFound do
    redirect_to root_path, alert: "Không tìm thấy tài nguyên."
  end

  before_action :set_locale

  # Ưu tiên: param hợp lệ > tùy chọn đã lưu của user > default (vi).
  # Whitelist chỉ vi/en — giá trị lạ rơi về default, không bao giờ raise
  # MissingTranslationData do locale không có trong whitelist.
  def set_locale
    I18n.locale =
      if User::LOCALES.include?(params[:locale].to_s)
        params[:locale]
      elsif current_user && User::LOCALES.include?(current_user.locale.to_s)
        current_user.locale
      else
        I18n.default_locale
      end
  end
end
