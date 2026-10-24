# frozen_string_literal: true

# Đặt biến môi trường tạm thời cho một ví dụ test, luôn khôi phục sau đó —
# kể cả khi ví dụ ném lỗi. Dùng nil để xoá biến.
module EnvHelper
  def with_env(vars)
    previous = vars.keys.to_h { |k| [k.to_s, ENV.fetch(k.to_s, nil)] }
    vars.each { |k, v| v.nil? ? ENV.delete(k.to_s) : ENV[k.to_s] = v.to_s }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

RSpec.configure { |config| config.include EnvHelper }
