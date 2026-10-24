require "rails_helper"

RSpec.describe "Client portal scope", type: :request do
  let(:org) { create(:organization) }
  let!(:client_user) { create(:user) }
  let!(:membership) { create(:membership, organization: org, user: client_user, role: "client") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(client_user)
    allow_any_instance_of(ApplicationController).to receive(:current_organization).and_return(org)
    allow_any_instance_of(ApplicationController).to receive(:current_role).and_return("client")
  end

  it "client không truy cập được CRM clients qua URL trực tiếp" do
    get clients_path
    expect(response).to redirect_to(root_path)
  end

  it "client không truy cập templates / content studio / members" do
    get templates_path
    expect(response).to redirect_to(root_path)
    get content_studio_path
    expect(response).to redirect_to(root_path)
    get members_path
    expect(response).to redirect_to(root_path)
  end

  it "client KHÔNG thấy campaign chưa được mời qua direct URL" do
    campaign = create(:campaign, organization: org)
    get campaign_path(campaign)
    expect(response).to redirect_to(root_path)
  end

  it "client thấy campaign được mời; không thấy artifact của campaign khác" do
    invited = create(:campaign, organization: org)
    other = create(:campaign, organization: org)
    invited.campaign_collaborators.create!(user: client_user, access: "comment")
    invited_artifact = create(:artifact, campaign: invited)
    other_artifact = create(:artifact, campaign: other)

    get campaign_path(invited)
    expect(response).to have_http_status(:ok)

    get artifact_path(invited_artifact)
    expect(response).to have_http_status(:ok)

    get artifact_path(other_artifact)
    expect(response).to redirect_to(root_path)
  end
end
