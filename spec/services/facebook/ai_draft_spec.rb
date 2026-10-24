require "rails_helper"

RSpec.describe Ai::Workflows::FacebookPostDraft do
  let(:org) { create(:organization) }
  let(:user) { create(:user) }
  let!(:m) { create(:membership, organization: org, user: user, role: "owner") }
  let(:conn) { create(:facebook_page_connection, organization: org) }

  it "sinh nháp offline (fake adapter): caption + hashtag + CTA, luôn draft, có audit + ai_run" do
    campaign = create(:campaign, organization: org)
    post = described_class.call(connection: conn, user: user, brief: "Khai trương chi nhánh mới", campaign: campaign, goal: "tăng khách")
    expect(post).to be_draft
    expect(post.ai_generated).to be true
    expect(post.message).to include("#")
    expect(post.hashtags).not_to be_empty
    expect(post.call_to_action).to be_present
    expect(post.image_suggestions).not_to be_empty
    expect(AiRun.where(workflow: "facebook_post_draft").count).to eq(1)
    expect(AuditLog.where(action: "facebook.post.ai_drafted").count).to eq(1)
    expect(FacebookPost.where(status: "published").count).to eq(0)
  end
end
