# frozen_string_literal: true

module Facebook
  # Danh bạ hội nhóm Facebook (nhập tay). Không gọi Facebook.
  # Quyền: xem = nội bộ; thêm/sửa = edit; xoá = manage.
  class GroupsController < ApplicationController
    before_action -> { require_internal! }
    before_action :set_group, only: %i[edit update destroy]

    def index
      scope = current_organization.facebook_groups.includes(:default_assignee).ordered
      @tag = params[:tag].presence
      @show_inactive = params[:inactive] == "1"
      scope = scope.active unless @show_inactive
      scope = scope.where("LOWER(tags) LIKE ?", "%#{FacebookGroup.sanitize_sql_like(@tag.downcase)}%") if @tag
      @groups = scope.to_a
      @tags = FacebookGroup.all_tags(current_organization)
      @stats = FacebookGroupShare.in_org(current_organization).where(facebook_group_id: @groups.map(&:id))
                                 .group(:facebook_group_id, :status).count
    end

    def new
      return unless require_role!(:edit)

      @group = current_organization.facebook_groups.new(allows_links: true, active: true)
      load_form_options
    end

    def create
      return unless require_role!(:edit)

      @group = current_organization.facebook_groups.new(group_params.merge(created_by: current_user))
      if @group.save
        AuditLog.record!(org: current_organization, user: current_user, action: "facebook.group.created", subject: @group,
                         details: { "name" => @group.name, "url" => @group.url })
        redirect_to facebook_groups_path, notice: t("marketingos.facebook_groups.groups.created", name: @group.name)
      else
        load_form_options
        render :new, status: :unprocessable_content
      end
    end

    def edit
      return unless require_role!(:edit)

      load_form_options
    end

    def update
      return unless require_role!(:edit)

      if @group.update(group_params)
        AuditLog.record!(org: current_organization, user: current_user, action: "facebook.group.updated", subject: @group,
                         details: { "changed" => @group.saved_changes.keys - %w[updated_at] })
        redirect_to facebook_groups_path, notice: t("marketingos.facebook_groups.groups.updated", name: @group.name)
      else
        load_form_options
        render :edit, status: :unprocessable_content
      end
    end

    # Nhóm đã có lịch sử chia sẻ thì không xoá (giữ báo cáo) — chỉ ẩn đi.
    def destroy
      return unless require_role!(:manage)

      if @group.facebook_group_shares.exists?
        @group.update!(active: false)
        notice = t("marketingos.facebook_groups.groups.deactivated", name: @group.name)
      else
        @group.destroy!
        notice = t("marketingos.facebook_groups.groups.deleted", name: @group.name)
      end
      AuditLog.record!(org: current_organization, user: current_user, action: "facebook.group.removed", subject: @group,
                       details: { "name" => @group.name, "deleted" => @group.destroyed? })
      redirect_to facebook_groups_path, notice: notice
    end

    private

    def set_group
      @group = current_organization.facebook_groups.find(params[:id])
    end

    def group_params
      params.fetch(:group, {}).permit(:name, :url, :tags, :rules_note, :allows_links, :active, :default_assignee_id)
    end

    def load_form_options
      @assignees = FacebookGroupShare.assignable_users(current_organization)
    end
  end
end
