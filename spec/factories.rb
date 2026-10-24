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
