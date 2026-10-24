class SessionsController < ApplicationController
  skip_before_action :require_login
  layout "application"
  def new; end

  def create
    user = User.find_by(email: params[:email].to_s.downcase.strip)
    if user&.authenticate(params[:password])
      session[:user_id] = user.id
      session[:org_id] = user.organizations.first&.id
      AuditLog.record!(org: user.organizations.first || Organization.new, user: user, action: "auth.login")
      redirect_to root_path, notice: "Đăng nhập thành công."
    else
      flash.now[:alert] = "Email hoặc mật khẩu không đúng."
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    session.clear
    redirect_to login_path, notice: "Đã đăng xuất."
  end
end
