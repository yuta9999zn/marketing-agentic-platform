# Facebook Fanpage auto-publishing module.
#
# - facebook_page_connections: một Page đã kết nối cho organization. Page token
#   lưu MÃ HOÁ (access_token_ciphertext), không bao giờ trả ra frontend/log.
# - facebook_authorizations: trạng thái tạm sau OAuth callback (danh sách Page
#   được quản lý + token tương ứng, mã hoá) cho tới khi người dùng chọn Page.
#   Hết hạn sau 15 phút.
# - facebook_posts: bài đăng với state machine draft → pending_approval →
#   approved → scheduled → publishing → published | failed | cancelled.
# - facebook_publish_attempts: nhật ký từng lần gọi Graph API (retry, lỗi).
class CreateFacebookPublishing < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :facebook_publishing_paused, :boolean, default: false, null: false
    add_column :campaigns, :facebook_auto_publish, :boolean, default: false, null: false

    create_table :facebook_page_connections do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :connected_by, foreign_key: { to_table: :users }
      t.string :page_id, null: false
      t.string :page_name, null: false
      t.string :page_category
      t.string :page_link
      t.string :page_username
      t.string :picture_url
      t.text :access_token_ciphertext
      t.datetime :token_expires_at
      t.json :granted_scopes, default: []
      t.json :page_tasks, default: []
      t.string :status, null: false, default: "connected"
      t.string :last_error_code
      t.text :last_error
      t.datetime :last_checked_at
      t.datetime :disconnected_at
      t.boolean :auto_publish_enabled, default: false, null: false
      t.boolean :publishing_paused, default: false, null: false
      t.text :blocked_terms
      t.string :connection_mode, null: false, default: "live" # live | mock
      t.timestamps
    end
    add_index :facebook_page_connections, %i[organization_id page_id], unique: true

    create_table :facebook_authorizations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :user_token_ciphertext
      t.text :page_tokens_ciphertext
      t.json :pages, default: []
      t.json :granted_scopes, default: []
      t.string :page_hint
      t.datetime :token_expires_at
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.string :mode, null: false, default: "live"
      t.timestamps
    end

    create_table :facebook_posts do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :facebook_page_connection, null: false, foreign_key: true
      t.references :campaign, foreign_key: true
      t.references :artifact, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.string :title
      t.text :message
      t.string :link
      t.string :post_type, null: false, default: "text" # text | photo | link
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.string :timezone, null: false, default: "Asia/Ho_Chi_Minh"
      t.string :idempotency_key, null: false
      t.string :schedule_token
      t.integer :attempts, default: 0, null: false
      t.integer :max_attempts, default: 5, null: false
      t.datetime :next_attempt_at
      t.datetime :publish_started_at
      t.string :last_error_code
      t.string :error_kind # transient | permanent | unknown
      t.text :last_error
      t.string :facebook_post_id
      t.string :permalink_url
      t.datetime :published_at
      t.string :published_via # live | mock
      t.datetime :submitted_at
      t.datetime :approved_at
      t.string :approval_source # human | auto_publish
      t.text :rejection_note
      t.datetime :rejected_at
      t.datetime :cancelled_at
      t.boolean :ai_generated, default: false, null: false
      t.json :ai_metadata, default: {}
      t.timestamps
    end
    add_index :facebook_posts, :idempotency_key, unique: true
    add_index :facebook_posts, %i[status scheduled_at]
    add_index :facebook_posts, %i[facebook_page_connection_id facebook_post_id]

    create_table :facebook_publish_attempts do |t|
      t.references :facebook_post, null: false, foreign_key: true
      t.integer :attempt_number, null: false
      t.string :outcome, null: false, default: "started" # started | success | transient_failure | permanent_failure | skipped
      t.string :error_kind
      t.string :error_code
      t.string :error_subcode
      t.integer :http_status
      t.string :fbtrace_id
      t.text :error_message
      t.string :remote_post_id
      t.boolean :mock, default: false, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
