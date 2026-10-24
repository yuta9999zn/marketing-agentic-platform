# Additive migration — Phase 1..5 của implementation brief.
# Không xoá/sửa dữ liệu cũ; chỉ thêm cột/bảng + backfill an toàn.
class CreatePlatformFunctionality < ActiveRecord::Migration[8.0]
  def change
    # ── Phase 1: campaign mở rộng + milestones ──────────────────
    add_column :campaigns, :audience, :text
    add_column :campaigns, :channels, :string
    add_column :campaigns, :budget, :decimal, precision: 14, scale: 2
    add_column :campaigns, :brief_data, :json, default: {}
    add_column :campaigns, :lifecycle_stage, :string
    add_reference :campaigns, :owner, foreign_key: { to_table: :users }

    create_table :milestones do |t|
      t.references :campaign, null: false, foreign_key: true
      t.string :title, null: false
      t.string :state, null: false, default: "not_started"
      t.datetime :due_at
      t.text :blocker_reason
      t.references :owner, foreign_key: { to_table: :users }
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :milestones, %i[campaign_id position]
    add_reference :tasks, :milestone, foreign_key: true
    add_reference :tasks, :depends_on, foreign_key: { to_table: :tasks }

    # ── Phase 2: artifact editor fields + state chuẩn hoá ───────
    add_column :artifacts, :locale, :string, default: "vi"
    add_column :artifacts, :channel, :string
    add_column :artifacts, :due_date, :date
    add_column :artifacts, :source_note, :text
    reversible do |dir|
      dir.up do
        # pending → in_review theo state machine mới; giữ các giá trị khác.
        execute "UPDATE artifacts SET approval_status = 'in_review' WHERE approval_status = 'pending'"
      end
    end

    create_table :prompt_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :category, null: false
      t.string :name, null: false
      t.json :input_schema, default: {}
      t.text :instructions
      t.text :output_format
      t.string :locale, default: "vi"
      t.integer :version, null: false, default: 1
      t.references :owner, foreign_key: { to_table: :users }
      t.boolean :shared, null: false, default: true
      t.timestamps
    end

    create_table :project_templates do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.json :config, default: {} # milestones/tasks/artifact kinds defaults
      t.references :owner, foreign_key: { to_table: :users }
      t.boolean :shared, null: false, default: true
      t.timestamps
    end

    # ── Phase 3: approval rounds + decisions ────────────────────
    create_table :approval_rounds do |t|
      t.references :artifact, null: false, foreign_key: true
      t.integer :artifact_version, null: false
      t.references :requester, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending" # pending|approved|changes_requested|rejected|expired|cancelled
      t.date :due_date
      t.integer :quorum
      t.timestamps
    end
    add_index :approval_rounds, %i[artifact_id artifact_version]

    create_table :approval_decisions do |t|
      t.references :approval_round, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :decision, null: false # approved|changes_requested|rejected
      t.text :note
      t.timestamps
      t.index %i[approval_round_id user_id], unique: true # một reviewer, một decision/round
    end
    add_reference :approvals, :approval_round, foreign_key: true

    create_table :campaign_collaborators_tokens do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.string :token, null: false, index: { unique: true }
      t.string :email, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :accepted_at
      t.references :invited_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # ── Phase 4: event attendees + reminders ────────────────────
    create_table :event_attendees do |t|
      t.references :event, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :rsvp, null: false, default: "invited" # invited|yes|no|maybe
      t.timestamps
      t.index %i[event_id user_id], unique: true
    end

    create_table :reminders do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.datetime :run_at, null: false
      t.string :state, null: false, default: "queued" # queued|sent|failed|cancelled
      t.string :idempotency_key, null: false, index: { unique: true }
      t.json :payload, default: {}
      t.string :channel, null: false, default: "in_app"
      t.timestamps
    end

    # ── Phase 5: AI runs + workspace AI setting ─────────────────
    add_column :organizations, :ai_external_enabled, :boolean, null: false, default: false

    create_table :ai_runs do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, foreign_key: { to_table: :users }
      t.string :workflow, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.string :consent_status, null: false, default: "not_required"
      t.string :prompt_template_version
      t.json :input_references, default: {}
      t.references :output_artifact, foreign_key: { to_table: :artifacts }
      t.boolean :human_reviewed, null: false, default: false
      t.text :error_metadata
      t.timestamps
    end
  end
end
