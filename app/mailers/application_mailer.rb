class ApplicationMailer < ActionMailer::Base
  # Địa chỉ gửi lấy từ biến môi trường — mỗi lần gửi mới đọc, không ghim lúc
  # nạp class (để đổi MAIL_FROM không phải build lại image).
  default from: -> { ENV.fetch("MAIL_FROM", "no-reply@marketingos.local") }
  layout "mailer"
end
