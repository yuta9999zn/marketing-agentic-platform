# frozen_string_literal: true

module Ai
  module Workflows
    # Tổng hợp phản hồi khảo sát THẬT thành insight cho brief/persona.
    #
    # Nguyên tắc: chỉ được nói những gì có trong dữ liệu. Số lượng phản hồi ít
    # thì phải nói rõ là mẫu nhỏ, không được suy rộng — đúng tinh thần coverage
    # gate "học 1 hiểu 10" của harness: thiếu dữ liệu thì khai báo, không bịa.
    class SurveyInsight
      MIN_RESPONSES = 3 # dưới ngưỡng này chỉ tóm tắt, không rút insight

      SCHEMA = {
        "type" => "object",
        "required" => %w[summary insights missing_data],
        "properties" => {
          "summary" => { "type" => "string" },
          "insights" => { "type" => "array", "items" => { "type" => "string" } },
          "missing_data" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }.freeze

      def self.call(survey:, user:)
        responses = survey.survey_responses.order(:created_at).to_a
        raise ArgumentError, "Khảo sát chưa có phản hồi nào để phân tích." if responses.empty?

        campaign = survey.campaign
        prompt = build_prompt(survey, responses)
        gw = Gateway.new(org: campaign.organization, user: user,
                         fake_completion: fake_completion(survey, responses))
        result = gw.generate_structured(prompt: prompt, task: "survey.insight",
                                        schema: SCHEMA, consent_external: false)

        artifact = campaign.artifacts.create!(
          kind: "report",
          title: "Phân tích khảo sát — #{survey.title}",
          body: render_body(result, responses.size),
          created_by: user, ai_generated: true,
          ai_metadata: {
            "source" => "ai_workflow:survey_insight",
            "workflow" => "survey_insight",
            "provider" => gw.provider_label,
            "prompt_sha" => Digest::SHA256.hexdigest(prompt),
            "generated_at" => Time.current.iso8601,
            "consent_external" => false,
            "human_reviewed" => false,
            "survey_id" => survey.id,
            "response_count" => responses.size,
            "small_sample" => responses.size < MIN_RESPONSES,
            "missing_data" => result["missing_data"]
          }
        )
        AiRun.record!(org: campaign.organization, user: user, workflow: "survey_insight",
                      provider: gw.provider_label, model: gw.model_label.to_s,
                      input_references: { "survey_id" => survey.id, "responses" => responses.size },
                      output_artifact: artifact)
        AuditLog.record!(org: campaign.organization, user: user,
                         action: "ai.survey.analysed", subject: artifact)
        artifact
      end

      def self.build_prompt(survey, responses)
        questions = survey.question_list
        answers_block = responses.each_with_index.map do |r, i|
          lines = questions.filter_map do |q|
            value = r.answers[q["key"]]
            "  #{q['label']}: #{value}" if value.present?
          end
          "Phản hồi #{i + 1}#{r.respondent_label.present? ? " (#{r.respondent_label})" : ''}:\n#{lines.join("\n")}"
        end.join("\n\n")

        sample_warning =
          if responses.size < MIN_RESPONSES
            "CHỈ CÓ #{responses.size} phản hồi — mẫu quá nhỏ. Chỉ được tóm tắt những gì " \
            "người trả lời đã nói. TUYỆT ĐỐI không rút ra kết luận chung về thị trường, " \
            "và phải ghi vào missing_data rằng cần thêm phản hồi."
          else
            "Có #{responses.size} phản hồi. Chỉ rút insight khi có ít nhất hai phản hồi " \
            "cùng nói về một điểm; nêu rõ bao nhiêu người nhắc tới."
          end

        <<~PROMPT
          Bạn là chuyên viên nghiên cứu thị trường. Phân tích kết quả khảo sát dưới đây
          cho chiến dịch "#{survey.campaign.name}".

          #{sample_warning}

          Quy tắc bắt buộc:
          - Chỉ dùng thông tin có trong phản hồi. Không thêm số liệu, không suy đoán nhân khẩu học.
          - Không được tạo ra tỷ lệ phần trăm nếu không đếm được từ dữ liệu.
          - Thông tin cần mà khảo sát chưa hỏi → đưa vào missing_data.

          --- DỮ LIỆU KHẢO SÁT ---
          #{answers_block}

          Trả về JSON đúng schema:
          {"summary": "tóm tắt ngắn", "insights": ["..."], "missing_data": ["..."]}
        PROMPT
      end

      def self.render_body(result, count)
        parts = ["## Tóm tắt (#{count} phản hồi)", result["summary"].to_s]
        if Array(result["insights"]).any?
          parts << "\n## Insight"
          parts.concat(Array(result["insights"]).map { |i| "- #{i}" })
        end
        if Array(result["missing_data"]).any?
          parts << "\n## Còn thiếu dữ liệu"
          parts.concat(Array(result["missing_data"]).map { |m| "- #{m}" })
        end
        parts.join("\n")
      end

      # Chế độ mô phỏng: đếm thật từ dữ liệu, không bịa insight.
      def self.fake_completion(survey, responses)
        lambda do |_prompt|
          questions = survey.question_list
          counts = questions.map do |q|
            answered = responses.count { |r| r.answers[q["key"]].present? }
            "#{q['label']}: #{answered}/#{responses.size} người trả lời"
          end
          missing = []
          missing << "Mẫu quá nhỏ (#{responses.size} phản hồi) — cần thêm để rút kết luận" if responses.size < MIN_RESPONSES
          missing << "Chưa nối mô hình ngôn ngữ thật nên chỉ thống kê số lượt trả lời"
          { summary: "Khảo sát \"#{survey.title}\" thu được #{responses.size} phản hồi.",
            insights: counts, missing_data: missing }.to_json
        end
      end
    end
  end
end
