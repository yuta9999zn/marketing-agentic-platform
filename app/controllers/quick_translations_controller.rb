# Dịch nhanh tại chỗ. Chỉ dịch đúng văn bản người dùng gửi lên — không đọc
# artifact theo id, nên không có đường rò dữ liệu qua tham số.
#
# Endpoint JSON: phân quyền tự trả 403 JSON, KHÔNG dùng require_role!/require_internal!
# vì hai hàm đó redirect (đúng cho HTML, sai cho fetch).
class QuickTranslationsController < ApplicationController
  TARGET_LOCALES = %w[vi en ja ko zh].freeze

  def create
    return unless authorize_quick_translate

    result = Translations::QuickTranslate.call(
      text: params[:text], org: current_organization, user: current_user,
      target_locale: target_locale, source_locale: params[:source_locale]
    )
    render json: { ok: true, text: result.text, provider: result.provider,
                   truncated: result.truncated }
  rescue ArgumentError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  rescue Providers::AdapterFactory::ExternalNotConfigured, CDFLHarness::Errors::Error => e
    # Model không chạy hoặc không trả kết quả — nói thật, không trả bản dịch giả.
    render json: { ok: false, error: t("marketingos.quick_translate.failed", detail: e.message) },
           status: :service_unavailable
  end

  private

  # Có campaign_id → phải xem được campaign đó (client/external_reviewer dùng
  # được để đọc nội dung tiếng Việt). Không có → phải là người nội bộ.
  def authorize_quick_translate
    if params[:campaign_id].present?
      campaign = Campaign.in_org(current_organization).find_by(id: params[:campaign_id])
      return deny(:not_found, "Không tìm thấy campaign.") if campaign.nil?
      return deny(:forbidden) unless policy_for.allowed?(:view, subject: campaign)
    elsif !Authentication::INTERNAL_ROLES.include?(current_role.to_s)
      return deny(:forbidden)
    end
    true
  end

  def deny(status, message = nil)
    render json: { ok: false, error: message || t("marketingos.quick_translate.forbidden") },
           status: status
    false
  end

  def target_locale
    TARGET_LOCALES.include?(params[:target_locale].to_s) ? params[:target_locale] : "en"
  end
end
