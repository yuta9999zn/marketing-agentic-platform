# frozen_string_literal: true

module Facebook
  module Posts
    # Exponential backoff có giới hạn cho lỗi tạm thời: 1, 2, 4, 8, 16 phút (+ jitter ≤ 20%),
    # trần 30 phút. Lỗi vĩnh viễn (quyền, validation, policy) KHÔNG đi qua đây.
    class Backoff
      BASE = 60       # giây
      CAP = 30 * 60   # giây

      def self.delay_seconds(attempt, jitter: true)
        base = [ BASE * (2**[ attempt - 1, 0 ].max), CAP ].min
        return base unless jitter

        base + SecureRandom.random_number((base * 0.2).to_i + 1)
      end

      def self.next_attempt_at(attempt, from: Time.current, jitter: true)
        from + delay_seconds(attempt, jitter: jitter).seconds
      end
    end
  end
end
