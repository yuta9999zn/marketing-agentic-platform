class RegistrationsController < ApplicationController
  skip_before_action :require_login
  layout "application"

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    org_name = params[:organization_name].presence
    if @user.valid? && org_name
      ActiveRecord::Base.transaction do
        @user.save!
        org = Organization.create!(name: org_name)
        Membership.create!(organization: org, user: @user, role: "owner")
        AuditLog.record!(org: org, user: @user, action: "org.created", subject: org)
      end
      session[:user_id] = @user.id
      session[:org_id] = @user.organizations.first.id
      redirect_to root_path, notice: "Đã tạo workspace. Chúc bạn làm việc hiệu quả!"
    else
      @user.errors.add(:base, "Cần tên tổ chức") unless org_name
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    { email: params[:email].to_s.downcase.strip, name: params[:name], password: params[:password] }
  end
end
