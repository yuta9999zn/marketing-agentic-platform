# frozen_string_literal: true

module Facebook
  # Mã hoá token Page at rest: AES-256-GCM qua ActiveSupport::MessageEncryptor.
  #
  # Khoá: FACEBOOK_TOKEN_ENCRYPTION_KEY (khuyến nghị trên production — đổi
  # SECRET_KEY_BASE sẽ không làm mất token). Không có thì dẫn xuất từ
  # secret_key_base của app (đủ cho dev/test).
  #
  # Token đã giải mã chỉ sống trong bộ nhớ của tiến trình gọi Graph API —
  # không ghi log, không render, không serialize.
  class TokenCipher
    SALT = "facebook-page-access-token"

    class << self
      def encrypt(plain)
        return nil if plain.blank?

        encryptor.encrypt_and_sign(plain.to_s)
      end

      def decrypt(ciphertext)
        return nil if ciphertext.blank?

        encryptor.decrypt_and_verify(ciphertext)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
        raise Facebook::ConfigurationError,
              "Không giải mã được token Page — FACEBOOK_TOKEN_ENCRYPTION_KEY/SECRET_KEY_BASE đã đổi? Hãy kết nối lại Page."
      end

      def explicit_key? = ENV["FACEBOOK_TOKEN_ENCRYPTION_KEY"].present?

      private

      def encryptor
        ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
      end

      def key
        explicit = ENV["FACEBOOK_TOKEN_ENCRYPTION_KEY"].presence
        if explicit
          ActiveSupport::KeyGenerator.new(explicit, iterations: 1000).generate_key(SALT, 32)
        else
          Rails.application.key_generator.generate_key(SALT, 32)
        end
      end
    end
  end
end
