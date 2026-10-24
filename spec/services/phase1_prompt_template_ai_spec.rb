require "rails_helper"

# Phase 1 — prompt template được dùng thật trong workflow AI, và không được
# ghi đè invariant "decline thay vì bịa số liệu".
RSpec.describe "Prompt template trong workflow AI" do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let(:client) { create(:client, organization: org) }
  let(:campaign) { create(:campaign, organization: org, client: client) }

  before { create(:membership, organization: org, user: user, role: "strategist") }

  it "chèn hướng dẫn của template vào prompt và ghi lại phiên bản đã dùng" do
    template = PromptTemplate.create!(organization: org, name: "Kịch bản video", category: "video_script",
                                      instructions: "Hook 3 giây đầu phải chạm nỗi đau",
                                      output_format: "Hook / Thân / CTA", owner: user)

    prompt = Ai::Workflows::ScriptDraft.build_prompt(campaign, "video_script", nil, nil, nil, template)
    expect(prompt).to include("Hook 3 giây đầu phải chạm nỗi đau")
    expect(prompt).to include("Hook / Thân / CTA")
    expect(prompt).to include("Kịch bản video")
    # Invariant vẫn nằm SAU khối template — template không ghi đè được.
    expect(prompt.index("không bịa số liệu")).to be > prompt.index("Hook 3 giây đầu")
  end

  it "prompt không có template vẫn giữ ràng buộc không bịa số liệu" do
    prompt = Ai::Workflows::ScriptDraft.build_prompt(campaign, "social_post", nil, nil, nil, nil)
    expect(prompt).to include("không bịa số liệu")
  end

  it "tạo artifact có ghi nhận template trong audit AiRun" do
    template = PromptTemplate.create!(organization: org, name: "Bài social", category: "social_post",
                                      instructions: "Hook đứng độc lập", owner: user)

    artifact = Ai::Workflows::ScriptDraft.call(campaign: campaign, user: user, kind: "social_post",
                                                prompt_template: template)

    expect(artifact.ai_metadata["prompt_template_id"]).to eq(template.id)
    expect(artifact.ai_metadata["prompt_template_version"]).to eq("Bài social v1")
    expect(artifact.approval_status).to eq("draft")

    run = AiRun.last
    expect(run.prompt_template_version).to eq("Bài social v1")
    expect(run.input_references["prompt_template_id"]).to eq(template.id)
  end

  it "không lưu prompt thô — chỉ hash" do
    artifact = Ai::Workflows::ScriptDraft.call(campaign: campaign, user: user, kind: "social_post")
    expect(artifact.ai_metadata).to have_key("prompt_sha")
    expect(artifact.ai_metadata["prompt_sha"]).to match(/\A[0-9a-f]{64}\z/)
    expect(artifact.ai_metadata.values.join).not_to include("Viết bản nháp")
  end

end
