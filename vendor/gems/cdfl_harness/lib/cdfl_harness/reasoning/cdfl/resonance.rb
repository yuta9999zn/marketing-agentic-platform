# lib/cdfl_harness/reasoning/cdfl/resonance.rb
# frozen_string_literal: true

module CDFLHarness
  module Reasoning
    module CDFL
      # Vận hành hoá hệ số giao thoa γ — CẬP NHẬT theo Phụ lục F (F.4/F.5/F.11) của thesis
      # Nguyễn Trường An. Bản CDFL trước (V8–V11) chỉ thăm dò bằng InfoGain (novelty+uncertainty)
      # và coi γ như khái niệm. Bản đã sửa: γ là SKILL SCORE đo được; trục cam kết e suy từ σ; Tứ
      # Tượng suy từ (e, γ); và dò ĐỐM ĐEN phải dùng γ<0 so THỰC TẠI (không phải novelty/disagreement).
      #
      #   γ = [S(ρ‖u) − S(ρ‖σ)] / [S(ρ‖u) + S(ρ‖σ)]        (F.4)
      #   e = S(σ‖u) / (1 + S(σ‖u))                          (F.11)  — tính CHỈ từ σ
      #
      # Ghi chú v11: γ là thước đo SAU-KẾT-CỤC trên held-out, không đưa trực tiếp làm hàm mục tiêu
      # (kỷ luật chống Goodhart, F.11). Tại đây γ nối vào TransitionModel: σ = P(·|s,a), u = đều trên
      # known_states, ρ = kết cục s' quan sát được — chính là skill score của mô hình dịch chuyển.
      module Resonance
        module_function

        # γ từ hai độ tối (S(ρ‖u), S(ρ‖σ) ≥ 0). +1 cộng hưởng · 0 chưa giao thoa · −1 ảo tưởng.
        def gamma(dark_vs_u:, dark_vs_sigma:)
          a = [dark_vs_u.to_f, 0.0].max
          b = [dark_vs_sigma.to_f, 0.0].max
          return 0.0 if (a + b).zero?

          (a - b) / (a + b)
        end

        # e = s/(1+s), s = S(σ‖u)/D — cam kết (F.11, BẢN CHUẨN HOÁ THEO CHIỀU, mặc định từ 2026-08).
        # σ=u → 0; σ sắc → →1. `dims:` là SỐ CHIỀU mà `dark_sigma_vs_u` đã cộng dồn trên đó
        # (mặc định 1 = độ tối đã chuẩn hoá sẵn / trường hợp một chiều, khi đó trung bình ≡ tổng).
        #
        # VÌ SAO CHIA CHO D: e phải đo ĐỘ SẮC CỦA NIỀM TIN, không đo SỐ CHIỀU. Bản tổng cũ
        # (commitment_sum) khiến cùng một độ sắc thì hệ 30 chiều luôn "cam kết hơn" hệ 3 chiều —
        # vô lý — và bão hoà ở ~0,98 (D=30, σ≈0,05, σ0=0,30 ⇒ S≈53,7). Đo được: dải động e bản
        # tổng 0,178 so với γ 0,798; bản trung bình 0,588 (gấp 3,3×). Bản tổng làm mặt phẳng
        # Tứ Tượng (γ, e) SỤP THÀNH MỘT ĐƯỜNG. Bản trung bình bất biến theo D và giữ nguyên
        # hai đầu mút (σ=σ0 → e=0; σ→0 → e→1).
        def commitment(dark_sigma_vs_u:, dims: 1)
          d = [dims.to_i, 1].max
          s = [dark_sigma_vs_u.to_f / d, 0.0].max
          s / (1.0 + s)
        end

        # Tiện ích D-aware: e trực tiếp từ danh sách độ tán σ_i và bề rộng khám phá ban đầu σ0.
        # Đây là lối gọi ĐƯỢC KHUYẾN NGHỊ vì không thể quên chuẩn hoá theo chiều.
        def commitment_from_sigmas(sigmas:, sigma0:)
          list = Array(sigmas).map(&:to_f)
          return 0.0 if list.empty?

          total = list.sum { |x| Math.log(sigma0.to_f / [x, 1e-9].max) }
          commitment(dark_sigma_vs_u: total, dims: list.size)
        end

        # [LEGACY — không dùng cho đo đạc mới] Bản TỔNG cũ của F.11: e = S/(1+S) không chia D.
        # BÃO HOÀ THEO SỐ CHIỀU. Giữ nguyên văn chỉ để tái lập các số cũ và để so sánh công khai.
        def commitment_sum(dark_sigma_vs_u:)
          s = [dark_sigma_vs_u.to_f, 0.0].max
          s / (1.0 + s)
        end

        # γ vận hành hoá của MỘT dịch chuyển, đo bằng chính TransitionModel (skill score log-loss).
        #   σ = P(s'|s,a);  u = đều trên |known_states|;  ρ = s' quan sát.
        #   S(ρ‖u) = ln|known|;  S(ρ‖σ) = −ln P(s'|s,a).
        def gamma_for_transition(model, state, action, next_state)
          known = model.known_states.size
          return 0.0 if known <= 1

          p = model.probability(state, action, next_state)
          gamma(dark_vs_u: Math.log(known), dark_vs_sigma: -Math.log([p, 1e-12].max))
        end

        SIXIANG = {
          [true,  true]  => "Lão Dương — OR thật (e>0, γ>0)",
          [true,  false] => "Thiếu Âm — đốm tối (e>0, γ<0)",
          [false, true]  => "Thiếu Dương — đốm sáng (e≈0, kỳ vọng Δγ cao)",
          [false, false] => "Lão Âm — DE sâu (e≈0, γ≤0)"
        }.freeze

        # Tứ Tượng suy từ (e, γ) — F.5.
        def sixiang(e_val, gamma_val, e_thr: 0.1)
          SIXIANG[[e_val > e_thr, gamma_val > 0.0]]
        end

        # ĐỐM ĐEN = cam kết mà SAI (e>0, γ<0). Error-seek so THỰC TẠI: TN 6.5 cho thấy dò γ<0 tìm
        # 92,8% vùng khó, còn ensemble-disagreement/novelty né vùng khó (4,6%) và mù trước đốm tối.
        def black_dot?(e_val, gamma_val, e_thr: 0.1)
          e_val > e_thr && gamma_val < 0.0
        end
      end
    end
  end
end
