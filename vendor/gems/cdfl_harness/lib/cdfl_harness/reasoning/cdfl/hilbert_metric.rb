# lib/cdfl_harness/reasoning/cdfl/hilbert_metric.rb
# frozen_string_literal: true

require "matrix"

module CDFLHarness
  module Reasoning
    module CDFL
      # CDFL v10/v11 measurement primitives — the descriptive |OR| = I(I:M)
      # gauge. Port of hilbert_metric.py. DESCRIPTIVE ONLY: v11 showed active
      # action selection is no better than random, so this is never on the
      # action path — only an observability/diagnostic measure.
      #
      # Ruby stdlib has no complex Hermitian eigensolver, so we use the
      # real-embedding trick: a Hermitian H = A + iB maps to the real symmetric
      # 2n×2n matrix [[A, -B], [B, A]], whose eigenvalues equal H's eigenvalues
      # each doubled. We then use stdlib Matrix#eigensystem (real symmetric).
      module HilbertMetric
        EPS = 1e-12

        module_function

        # S(ρ) = -tr(ρ log ρ).
        def von_neumann_entropy(rho)
          evs = embedded_eigenvalues(rho)          # 2n eigenvalues (each true ev doubled)
          s = 0.0
          evs.each { |l| s -= l * Math.log(l) if l > EPS }
          s / 2.0                                  # undo the doubling
        end

        # tr_B(ρ_AB) if keep_first, else tr_A(ρ_AB). rho is (dim_keep*dim_trace)².
        def partial_trace(rho, dim_keep, dim_trace, keep_first: true)
          Matrix.build(dim_keep, dim_keep) do |a, c|
            acc = Complex(0, 0)
            dim_trace.times do |b|
              acc += if keep_first
                       rho[a * dim_trace + b, c * dim_trace + b]
                     else
                       # keep second subsystem: trace out the FIRST (dim_trace)
                       rho[b * dim_keep + a, b * dim_keep + c]
                     end
            end
            acc
          end
        end

        # I(I:M) = S(ρ_I) + S(ρ_M) - S(ρ_IM). The |OR| quantity (v11 verified).
        def mutual_information(rho_im, dim_i, dim_m)
          rho_i = partial_trace(rho_im, dim_i, dim_m, keep_first: true)
          rho_m = partial_trace(rho_im, dim_m, dim_i, keep_first: false)
          von_neumann_entropy(rho_i) + von_neumann_entropy(rho_m) - von_neumann_entropy(rho_im)
        end

        # DE = S(ρ‖σ) = tr(ρ ln ρ) − tr(ρ ln σ). The Dark-Existence quantity.
        def relative_entropy(rho, sigma)
          raise ArgumentError, "shape mismatch" unless rho.row_count == sigma.row_count

          tr_rho_ln_rho = -von_neumann_entropy(rho) # = Σ λ ln λ
          ln_sigma_embed = embedded_log(sigma)      # 2n×2n real symmetric ln(σ) embedding
          rho_embed = embed(rho)
          tr_rho_ln_sigma = (rho_embed * ln_sigma_embed).trace / 2.0
          [tr_rho_ln_rho - tr_rho_ln_sigma, 0.0].max
        end

        # |I0><I0| ⊗ |M0><M0|. I(I:M)=0.
        def make_pure_product_state(dim_i, dim_m)
          rho_i = Matrix.build(dim_i, dim_i) { |r, c| (r.zero? && c.zero?) ? Complex(1, 0) : Complex(0, 0) }
          rho_m = Matrix.build(dim_m, dim_m) { |r, c| (r.zero? && c.zero?) ? Complex(1, 0) : Complex(0, 0) }
          kron(rho_i, rho_m)
        end

        def kron(a, b)
          ra = a.row_count; ca = a.column_count
          rb = b.row_count; cb = b.column_count
          Matrix.build(ra * rb, ca * cb) { |i, j| a[i / rb, j / cb] * b[i % rb, j % cb] }
        end

        # ----- real-embedding helpers -----

        # Hermitian H = A + iB → real symmetric [[A, -B], [B, A]] (2n×2n).
        def embed(h)
          n = h.row_count
          Matrix.build(2 * n, 2 * n) do |i, j|
            block_i = i / n; block_j = j / n
            r = i % n; c = j % n
            z = h[r, c]
            case [block_i, block_j]
            when [0, 0], [1, 1] then z.real
            when [0, 1] then -z.imaginary
            else z.imaginary
            end
          end
        end

        def embedded_eigenvalues(h)
          embed(h).eigensystem.eigenvalues.map { |e| e.respond_to?(:real) ? e.real : e.to_f }
        end

        # ln(σ) in the embedding space (real symmetric), via eigendecomposition.
        def embedded_log(sigma)
          es = embed(sigma).eigensystem
          d = es.eigenvalues.map { |e| (e.respond_to?(:real) ? e.real : e.to_f) }
          v = es.eigenvector_matrix
          ln = Matrix.diagonal(*d.map { |x| Math.log([x, EPS].max) })
          (v * ln * v.transpose).map(&:real)
        end
      end
    end
  end
end
