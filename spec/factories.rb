FactoryBot.define do
  factory :organization do
    sequence(:name) { |n| "Org #{n}" }
  end

  factory :user do
    sequence(:email) { |n| "user#{n}@test.vn" }
    name { "Người dùng test" }
    password { "password123" }
  end

  factory :membership do
    organization
    user
    role { "manager" }
  end

  factory :client do
    organization
    sequence(:name) { |n| "Client #{n}" }
    industry { "F&B" }
  end

  factory :campaign do
    organization
    client { association :client, organization: instance.organization }
    sequence(:name) { |n| "Campaign #{n}" }
    status { "brief" }
    objective { "Tăng nhận diện thương hiệu" }
  end

  factory :artifact do
    campaign
    kind { "brief" }
    title { "Brief test" }
    body { "Nội dung brief" }
  end

  factory :invitation do
    organization
    email { "invitee@test.vn" }
    role { "copywriter" }
  end

  factory :event do
    campaign
    title { "Kickoff" }
    starts_at { 1.day.from_now }
    ends_at { 1.day.from_now + 1.hour }
  end
end

FactoryBot.define do
  factory :facebook_page_connection do
    organization
    page_id { "100000000000001" }
    page_name { "Demo Page" }
    page_category { "Marketing Agency" }
    connection_mode { "mock" }
    status { "connected" }
    granted_scopes { Facebook::Config::REQUIRED_SCOPES }
    page_tasks { %w[CREATE_CONTENT MANAGE] }
    access_token { "mock_page_token_1" }
  end

  factory :facebook_post do
    organization
    facebook_page_connection { association :facebook_page_connection, organization: instance.organization }
    message { "Xin chào từ MarketingOS #test" }
    post_type { "text" }
    timezone { "Asia/Ho_Chi_Minh" }
    status { "draft" }
  end
end
