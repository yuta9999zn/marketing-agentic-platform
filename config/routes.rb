Rails.application.routes.draw do
  root "dashboard#index"

  get "up" => "rails/health#show", as: :rails_health_check

  get "content-studio", to: "content_studio#index", as: :content_studio
  get "calendar", to: "calendar#index", as: :calendar
  get "templates", to: "templates#index", as: :templates
  resources :prompt_templates, only: %i[new create edit update destroy]

  get "settings", to: "user_settings#show", as: :settings
  patch "settings", to: "user_settings#update"

  post "quick-translate", to: "quick_translations#create", as: :quick_translate

  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get "signup", to: "registrations#new"
  post "signup", to: "registrations#create"

  get "invite/:token", to: "invite_acceptances#show", as: :accept_invite
  post "invite/:token", to: "invite_acceptances#accept"

  resources :campaigns do
    member do
      post :generate
      post :create_image_prompt
      post :set_lifecycle
      post :save_as_template
    end
    collection { post :create_from_template }
    resources :surveys, only: %i[create]
    resources :collaborators, only: %i[create destroy], shallow: true
    resources :campaign_invites, only: %i[create] do
      member { post :revoke }
    end
  end

  get "campaign-invite/:token", to: "campaign_invite_acceptances#show", as: :accept_campaign_invite
  post "campaign-invite/:token", to: "campaign_invite_acceptances#accept"

  resources :artifacts, only: %i[show edit update] do
    member do
      post :submit
      post :withdraw
      post :restore_version
      post :duplicate
      post :translate
    end
  end
  resources :surveys, only: %i[show update] do
    member { post :analyse }
    resources :survey_responses, only: %i[create]
  end
  resources :approvals, only: %i[create]
  resources :tasks, only: %i[create update]
  resources :comments, only: %i[create]
  resources :events, only: %i[create] do
    member do
      get :ics
      post :rsvp
    end
    resources :event_attendees, only: %i[create]
  end
  resources :clients, only: %i[index show create update]
  resources :notifications, only: %i[index] do
    collection { post :mark_read }
  end
  resources :members, only: %i[index] do
    collection { post :invite }
    member do
      post :revoke # :id là invitation
      patch :update_role
    end
  end
  patch "workspace/ai", to: "workspace_settings#update_ai", as: :update_workspace_ai

  # Facebook Fanpage: kết nối OAuth + duyệt + lên lịch + đăng tự động.
  namespace :facebook do
    resource :connection, only: %i[show update destroy] do
      post :start          # bắt đầu OAuth (nhận link fanpage làm gợi ý)
      get :callback        # redirect URI đăng ký trong Meta App
      post :select_page    # chọn Page từ danh sách đã uỷ quyền
      post :check          # chạy chẩn đoán
      post :kill_switch    # tạm dừng/mở toàn workspace (admin)
    end
    resources :posts do
      collection { post :generate }
      member do
        post :submit
        post :approve
        post :reject
        post :schedule
        post :unschedule
        post :publish_now
        post :cancel
        post :retry
        post :reopen
      end
    end
  end
end
