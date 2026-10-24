# Hỗ trợ chia sẻ bài vào hội nhóm Facebook BẰNG TAY.
#
# Meta đã gỡ Groups API (Graph API v19.0, 2024) nên không app nào đăng vào nhóm
# được bằng cách chính thức. Module này không gọi Facebook: nó lưu danh sách
# nhóm, lên lịch "lượt chia sẻ" cho từng nhóm, nhắc người phụ trách đúng giờ và
# ghi lại kết quả do người dùng tự đánh dấu.
#
# - facebook_groups: danh bạ nhóm của workspace (nhập tay).
# - facebook_group_shares: một bài Page đã đăng × một nhóm. Trạng thái
#   pending → posted | rejected | skipped (mở lại được về pending).
class CreateFacebookGroupSharing < ActiveRecord::Migration[8.0]
  def change
    create_table :facebook_groups do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :default_assignee, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :url, null: false
      t.string :tags                                   # phân tách bằng dấu phẩy
      t.text :rules_note                               # luật nhóm: giờ đăng, cấm link...
      t.boolean :allows_links, null: false, default: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :facebook_groups, %i[organization_id url], unique: true

    create_table :facebook_group_shares do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :facebook_post, null: false, foreign_key: true
      t.references :facebook_group, null: false, foreign_key: true
      t.references :assignee, null: false, foreign_key: { to_table: :users }
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :completed_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending" # pending | posted | rejected | skipped
      t.datetime :scheduled_at, null: false
      t.datetime :completed_at
      t.text :message                                  # biến thể nội dung riêng cho nhóm (nil = dùng nội dung bài Page)
      t.boolean :ai_variant, null: false, default: false
      t.string :group_post_url                         # link bài trong nhóm, người dùng dán sau khi đăng
      t.text :note
      t.timestamps
    end
    add_index :facebook_group_shares, %i[facebook_post_id facebook_group_id], unique: true
    add_index :facebook_group_shares, %i[organization_id status scheduled_at]
    add_index :facebook_group_shares, %i[assignee_id status]
  end
end
