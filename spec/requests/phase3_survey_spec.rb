require "rails_helper"

# Phase 3 — khảo sát và AI phân tích thành insight.
RSpec.describe "Khảo sát", type: :request do
  let(:org) { create(:organization) }
  let(:manager) { create(:user) }
  let(:client_user) { create(:user) }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  before do
    create(:membership, organization: org, user: manager, role: "manager")
    create(:membership, organization: org, user: client_user, role: "client")
  end

  def make_survey(status: "open")
    campaign.surveys.create!(title: "Thói quen cà phê", status: status, created_by: manager,
                             questions: [{ "key" => "khi_nao", "label" => "Bạn mua lúc nào?", "kind" => "text" },
                                         { "key" => "vi_sao", "label" => "Vì sao chọn quán?", "kind" => "text" }])
  end

  describe "tạo khảo sát" do
    it "mỗi dòng thành một câu hỏi, khóa sinh tự động" do
      login_as(manager)
      post campaign_surveys_path(campaign),
           params: { title: "Khảo sát A", questions: "Câu một?\n\nCâu hai?\n" }

      survey = Survey.last
      expect(survey.question_list.map { |q| q["label"] }).to eq(["Câu một?", "Câu hai?"])
      expect(survey.status).to eq("draft")
      expect(survey.campaign).to eq(campaign)
    end

    it "client không tạo được khảo sát" do
      CampaignCollaborator.create!(campaign: campaign, user: client_user, access: "comment")
      login_as(client_user)
      expect {
        post campaign_surveys_path(campaign), params: { title: "Lén", questions: "x?" }
      }.not_to change(Survey, :count)
    end

    it "không tạo được khảo sát trên campaign của tổ chức khác" do
      foreign = create(:campaign, organization: create(:organization))
      login_as(manager)
      post campaign_surveys_path(foreign), params: { title: "X", questions: "y?" }
      expect(response).to redirect_to(root_path)
      expect(Survey.count).to eq(0)
    end
  end

  describe "nhận phản hồi" do
    it "chỉ nhận khi khảo sát đang mở" do
      survey = make_survey(status: "draft")
      login_as(manager)
      expect {
        post survey_survey_responses_path(survey), params: { answers: { "khi_nao" => "7h sáng" } }
      }.not_to change(SurveyResponse, :count)
    end

    it "loại bỏ khóa lạ, chỉ giữ câu trả lời khớp câu hỏi" do
      survey = make_survey
      login_as(manager)
      post survey_survey_responses_path(survey),
           params: { answers: { "khi_nao" => "7h sáng", "khoa_la" => "dữ liệu chèn thêm" },
                     respondent_label: "Chị Mai" }

      answers = SurveyResponse.last.answers
      expect(answers).to eq({ "khi_nao" => "7h sáng" })
      expect(answers).not_to have_key("khoa_la")
    end

    it "từ chối phản hồi trống rỗng" do
      survey = make_survey
      login_as(manager)
      expect {
        post survey_survey_responses_path(survey), params: { answers: { "khi_nao" => "  " } }
      }.not_to change(SurveyResponse, :count)
    end

    it "khách hàng được mời vào campaign cũng trả lời được" do
      survey = make_survey
      CampaignCollaborator.create!(campaign: campaign, user: client_user, access: "view")
      login_as(client_user)
      expect {
        post survey_survey_responses_path(survey), params: { answers: { "khi_nao" => "8h" } }
      }.to change(SurveyResponse, :count).by(1)
    end

    it "người ngoài campaign không trả lời được" do
      survey = make_survey
      login_as(client_user) # client nhưng KHÔNG được mời vào campaign
      expect {
        post survey_survey_responses_path(survey), params: { answers: { "khi_nao" => "8h" } }
      }.not_to change(SurveyResponse, :count)
    end
  end

  describe "AI phân tích" do
    it "từ chối khi chưa có phản hồi nào" do
      survey = make_survey
      login_as(manager)
      expect { post analyse_survey_path(survey) }.not_to change(Artifact, :count)
      expect(response).to redirect_to(survey_path(survey))
    end

    it "tạo bản phân tích là DRAFT chờ duyệt, ghi rõ số phản hồi" do
      survey = make_survey
      3.times { |i| survey.survey_responses.create!(answers: { "khi_nao" => "#{7 + i}h sáng" }) }

      login_as(manager)
      post analyse_survey_path(survey)

      artifact = Artifact.last
      expect(artifact.kind).to eq("report")
      expect(artifact.approval_status).to eq("draft")
      expect(artifact.ai_generated).to be true
      expect(artifact.ai_metadata["response_count"]).to eq(3)
      expect(artifact.ai_metadata["small_sample"]).to be false
      expect(artifact.ai_metadata).to have_key("prompt_sha")
    end

    it "mẫu dưới ngưỡng thì đánh dấu small_sample và cảnh báo trong prompt" do
      survey = make_survey
      survey.survey_responses.create!(answers: { "khi_nao" => "7h" })

      prompt = Ai::Workflows::SurveyInsight.build_prompt(survey, survey.survey_responses.to_a)
      expect(prompt).to include("mẫu quá nhỏ")
      expect(prompt).to include("không rút ra kết luận chung")

      login_as(manager)
      post analyse_survey_path(survey)
      expect(Artifact.last.ai_metadata["small_sample"]).to be true
    end

    it "prompt cấm bịa số liệu và tỷ lệ" do
      survey = make_survey
      3.times { survey.survey_responses.create!(answers: { "khi_nao" => "7h" }) }
      prompt = Ai::Workflows::SurveyInsight.build_prompt(survey, survey.survey_responses.to_a)

      expect(prompt).to include("Chỉ dùng thông tin có trong phản hồi")
      expect(prompt).to include("Không được tạo ra tỷ lệ phần trăm nếu không đếm được từ dữ liệu")
    end

    it "client không chạy được phân tích" do
      survey = make_survey
      survey.survey_responses.create!(answers: { "khi_nao" => "7h" })
      CampaignCollaborator.create!(campaign: campaign, user: client_user, access: "comment")
      login_as(client_user)
      expect { post analyse_survey_path(survey) }.not_to change(Artifact, :count)
    end
  end

  describe "xem khảo sát" do
    it "không xem được khảo sát của tổ chức khác" do
      foreign_campaign = create(:campaign, organization: create(:organization))
      foreign = foreign_campaign.surveys.create!(title: "Ngoài", questions: [])
      login_as(manager)
      get survey_path(foreign)
      expect(response).to redirect_to(root_path)
    end

    it "đổi trạng thái phải nằm trong danh sách hợp lệ" do
      survey = make_survey(status: "draft")
      login_as(manager)
      patch survey_path(survey), params: { status: "hacked" }
      expect(survey.reload.status).to eq("draft")

      patch survey_path(survey), params: { status: "open" }
      expect(survey.reload.status).to eq("open")
    end
  end
end
