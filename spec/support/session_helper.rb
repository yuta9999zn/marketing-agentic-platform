# frozen_string_literal: true

# Đăng nhập QUA ENDPOINT THẬT (POST /login) cho request specs —
# không stub current_user/current_role với security-critical flow.
module SessionHelper
  def login_as(user)
    post login_path, params: { email: user.email, password: "password123" }
    assert_redirected_to root_path
  end
end

RSpec.configure do |config|
  config.include SessionHelper, type: :request
end
