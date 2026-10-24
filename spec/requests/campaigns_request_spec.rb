require "rails_helper"

RSpec.describe "Campaigns", type: :request do
  let(:org) { create(:organization) }
  let(:manager) { create(:user) }
  let!(:membership) { create(:membership, organization: org, user: manager, role: "manager") }
  let(:client_record) { create(:client, organization: org) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(manager)
    allow_any_instance_of(ApplicationController).to receive(:current_organization).and_return(org)
    allow_any_instance_of(ApplicationController).to receive(:current_role).and_return("manager")
  end

  it "trang chủ hiển thị dashboard sau khi đăng nhập" do
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "tạo campaign và redirect" do
    expect {
      post campaigns_path, params: { campaign: { client_id: client_record.id, name: "Test camp", objective: "abc" } }
    }.to change(Campaign, :count).by(1)
    expect(response).to redirect_to(campaign_path(Campaign.last))
  end

  it "generate tạo artifact brief offline qua Fake adapter" do
    campaign = create(:campaign, organization: org, client: client_record)
    expect {
      post generate_campaign_path(campaign, kind: "brief")
    }.to change { campaign.artifacts.count }.by(1)
    expect(campaign.artifacts.last.ai_generated).to be true
  end

  it "không truy cập được campaign tổ chức khác (cô lập tenant)" do
    other_org = create(:organization)
    other_campaign = create(:campaign, organization: other_org)
    get campaign_path(other_campaign)
    expect(response).to redirect_to(root_path)
  end
end
