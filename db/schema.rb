# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_10_24_090001) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_calls", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id"
    t.string "task", null: false
    t.string "model", null: false
    t.string "method", null: false
    t.string "prompt_sha", null: false
    t.string "output_sha"
    t.boolean "repaired", default: false, null: false
    t.integer "latency_ms"
    t.string "status", default: "ok", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_ai_calls_on_organization_id"
    t.index ["user_id"], name: "index_ai_calls_on_user_id"
  end

  create_table "ai_runs", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id"
    t.string "workflow", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.string "consent_status", default: "not_required", null: false
    t.string "prompt_template_version"
    t.json "input_references", default: {}
    t.integer "output_artifact_id"
    t.boolean "human_reviewed", default: false, null: false
    t.text "error_metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_ai_runs_on_organization_id"
    t.index ["output_artifact_id"], name: "index_ai_runs_on_output_artifact_id"
    t.index ["user_id"], name: "index_ai_runs_on_user_id"
  end

  create_table "approval_decisions", force: :cascade do |t|
    t.integer "approval_round_id", null: false
    t.integer "user_id", null: false
    t.string "decision", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approval_round_id", "user_id"], name: "index_approval_decisions_on_approval_round_id_and_user_id", unique: true
    t.index ["approval_round_id"], name: "index_approval_decisions_on_approval_round_id"
    t.index ["user_id"], name: "index_approval_decisions_on_user_id"
  end

  create_table "approval_rounds", force: :cascade do |t|
    t.integer "artifact_id", null: false
    t.integer "artifact_version", null: false
    t.integer "requester_id"
    t.string "status", default: "pending", null: false
    t.date "due_date"
    t.integer "quorum"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "reviewer_ids"
    t.index ["artifact_id", "artifact_version"], name: "index_approval_rounds_on_artifact_id_and_artifact_version"
    t.index ["artifact_id"], name: "index_approval_rounds_on_artifact_id"
    t.index ["requester_id"], name: "index_approval_rounds_on_requester_id"
  end

  create_table "approvals", force: :cascade do |t|
    t.integer "artifact_id", null: false
    t.integer "user_id", null: false
    t.string "decision", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "approval_round_id"
    t.index ["approval_round_id"], name: "index_approvals_on_approval_round_id"
    t.index ["artifact_id"], name: "index_approvals_on_artifact_id"
    t.index ["user_id"], name: "index_approvals_on_user_id"
  end

  create_table "artifact_versions", force: :cascade do |t|
    t.integer "artifact_id", null: false
    t.text "body"
    t.integer "version", null: false
    t.boolean "ai_generated", default: false, null: false
    t.json "ai_metadata", default: {}
    t.integer "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artifact_id"], name: "index_artifact_versions_on_artifact_id"
    t.index ["created_by_id"], name: "index_artifact_versions_on_created_by_id"
  end

  create_table "artifacts", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "kind", null: false
    t.string "title", null: false
    t.text "body"
    t.boolean "ai_generated", default: false, null: false
    t.json "ai_metadata", default: {}
    t.string "approval_status", default: "draft", null: false
    t.integer "version", default: 1, null: false
    t.boolean "template", default: false, null: false
    t.integer "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale", default: "vi"
    t.string "channel"
    t.date "due_date"
    t.text "source_note"
    t.index ["campaign_id"], name: "index_artifacts_on_campaign_id"
    t.index ["created_by_id"], name: "index_artifacts_on_created_by_id"
  end

  create_table "audit_logs", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id"
    t.string "action", null: false
    t.string "subject_type"
    t.bigint "subject_id"
    t.json "details", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_audit_logs_on_organization_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "campaign_collaborator_tokens", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "campaign_id", null: false
    t.string "token", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "accepted_at"
    t.integer "invited_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "access"
    t.index ["campaign_id"], name: "index_campaign_collaborator_tokens_on_campaign_id"
    t.index ["invited_by_id"], name: "index_campaign_collaborator_tokens_on_invited_by_id"
    t.index ["organization_id"], name: "index_campaign_collaborator_tokens_on_organization_id"
    t.index ["token"], name: "index_campaign_collaborator_tokens_on_token", unique: true
  end

  create_table "campaign_collaborators", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "user_id", null: false
    t.string "access", default: "view", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "user_id"], name: "index_campaign_collaborators_on_campaign_id_and_user_id", unique: true
    t.index ["campaign_id"], name: "index_campaign_collaborators_on_campaign_id"
    t.index ["user_id"], name: "index_campaign_collaborators_on_user_id"
  end

  create_table "campaigns", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "client_id", null: false
    t.string "name", null: false
    t.string "status", default: "draft", null: false
    t.text "objective"
    t.date "start_date"
    t.date "end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "audience"
    t.string "channels"
    t.decimal "budget", precision: 14, scale: 2
    t.json "brief_data", default: {}
    t.string "lifecycle_stage"
    t.integer "owner_id"
    t.boolean "facebook_auto_publish", default: false, null: false
    t.index ["client_id"], name: "index_campaigns_on_client_id"
    t.index ["organization_id"], name: "index_campaigns_on_organization_id"
    t.index ["owner_id"], name: "index_campaigns_on_owner_id"
  end

  create_table "clients", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "name", null: false
    t.string "industry"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "contact_name"
    t.string "contact_email"
    t.string "contact_phone"
    t.index ["organization_id"], name: "index_clients_on_organization_id"
  end

  create_table "comments", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.integer "artifact_id"
    t.integer "user_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["artifact_id"], name: "index_comments_on_artifact_id"
    t.index ["campaign_id"], name: "index_comments_on_campaign_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "event_attendees", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "user_id", null: false
    t.string "rsvp", default: "invited", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "user_id"], name: "index_event_attendees_on_event_id_and_user_id", unique: true
    t.index ["event_id"], name: "index_event_attendees_on_event_id"
    t.index ["user_id"], name: "index_event_attendees_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "title", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "location"
    t.text "agenda"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_events_on_campaign_id"
  end

  create_table "facebook_authorizations", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id", null: false
    t.text "user_token_ciphertext"
    t.text "page_tokens_ciphertext"
    t.json "pages", default: []
    t.json "granted_scopes", default: []
    t.string "page_hint"
    t.datetime "token_expires_at"
    t.datetime "expires_at", null: false
    t.datetime "consumed_at"
    t.string "mode", default: "live", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_facebook_authorizations_on_organization_id"
    t.index ["user_id"], name: "index_facebook_authorizations_on_user_id"
  end

  create_table "facebook_page_connections", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "connected_by_id"
    t.string "page_id", null: false
    t.string "page_name", null: false
    t.string "page_category"
    t.string "page_link"
    t.string "page_username"
    t.string "picture_url"
    t.text "access_token_ciphertext"
    t.datetime "token_expires_at"
    t.json "granted_scopes", default: []
    t.json "page_tasks", default: []
    t.string "status", default: "connected", null: false
    t.string "last_error_code"
    t.text "last_error"
    t.datetime "last_checked_at"
    t.datetime "disconnected_at"
    t.boolean "auto_publish_enabled", default: false, null: false
    t.boolean "publishing_paused", default: false, null: false
    t.text "blocked_terms"
    t.string "connection_mode", default: "live", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connected_by_id"], name: "index_facebook_page_connections_on_connected_by_id"
    t.index ["organization_id", "page_id"], name: "index_facebook_page_connections_on_organization_id_and_page_id", unique: true
    t.index ["organization_id"], name: "index_facebook_page_connections_on_organization_id"
  end

  create_table "facebook_posts", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "facebook_page_connection_id", null: false
    t.integer "campaign_id"
    t.integer "artifact_id"
    t.integer "created_by_id"
    t.integer "approved_by_id"
    t.string "title"
    t.text "message"
    t.string "link"
    t.string "post_type", default: "text", null: false
    t.string "status", default: "draft", null: false
    t.datetime "scheduled_at"
    t.string "timezone", default: "Asia/Ho_Chi_Minh", null: false
    t.string "idempotency_key", null: false
    t.string "schedule_token"
    t.integer "attempts", default: 0, null: false
    t.integer "max_attempts", default: 5, null: false
    t.datetime "next_attempt_at"
    t.datetime "publish_started_at"
    t.string "last_error_code"
    t.string "error_kind"
    t.text "last_error"
    t.string "facebook_post_id"
    t.string "permalink_url"
    t.datetime "published_at"
    t.string "published_via"
    t.datetime "submitted_at"
    t.datetime "approved_at"
    t.string "approval_source"
    t.text "rejection_note"
    t.datetime "rejected_at"
    t.datetime "cancelled_at"
    t.boolean "ai_generated", default: false, null: false
    t.json "ai_metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_facebook_posts_on_approved_by_id"
    t.index ["artifact_id"], name: "index_facebook_posts_on_artifact_id"
    t.index ["campaign_id"], name: "index_facebook_posts_on_campaign_id"
    t.index ["created_by_id"], name: "index_facebook_posts_on_created_by_id"
    t.index ["facebook_page_connection_id", "facebook_post_id"], name: "idx_on_facebook_page_connection_id_facebook_post_id_670a260eeb"
    t.index ["facebook_page_connection_id"], name: "index_facebook_posts_on_facebook_page_connection_id"
    t.index ["idempotency_key"], name: "index_facebook_posts_on_idempotency_key", unique: true
    t.index ["organization_id"], name: "index_facebook_posts_on_organization_id"
    t.index ["status", "scheduled_at"], name: "index_facebook_posts_on_status_and_scheduled_at"
  end

  create_table "facebook_publish_attempts", force: :cascade do |t|
    t.integer "facebook_post_id", null: false
    t.integer "attempt_number", null: false
    t.string "outcome", default: "started", null: false
    t.string "error_kind"
    t.string "error_code"
    t.string "error_subcode"
    t.integer "http_status"
    t.string "fbtrace_id"
    t.text "error_message"
    t.string "remote_post_id"
    t.boolean "mock", default: false, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["facebook_post_id"], name: "index_facebook_publish_attempts_on_facebook_post_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "email", null: false
    t.string "role", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "accepted_at"
    t.integer "invited_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["organization_id"], name: "index_invitations_on_organization_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id", null: false
    t.string "role", default: "member", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "user_id"], name: "index_memberships_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "milestones", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "title", null: false
    t.string "state", default: "not_started", null: false
    t.datetime "due_at"
    t.text "blocker_reason"
    t.integer "owner_id"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "position"], name: "index_milestones_on_campaign_id_and_position"
    t.index ["campaign_id"], name: "index_milestones_on_campaign_id"
    t.index ["owner_id"], name: "index_milestones_on_owner_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "organization_id", null: false
    t.string "kind", null: false
    t.json "payload", default: {}
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_notifications_on_organization_id"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "ai_external_enabled", default: false, null: false
    t.boolean "facebook_publishing_paused", default: false, null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
  end

  create_table "project_templates", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "name", null: false
    t.text "description"
    t.json "config", default: {}
    t.integer "owner_id"
    t.boolean "shared", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_project_templates_on_organization_id"
    t.index ["owner_id"], name: "index_project_templates_on_owner_id"
  end

  create_table "prompt_templates", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.string "category", null: false
    t.string "name", null: false
    t.json "input_schema", default: {}
    t.text "instructions"
    t.text "output_format"
    t.string "locale", default: "vi"
    t.integer "version", default: 1, null: false
    t.integer "owner_id"
    t.boolean "shared", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_prompt_templates_on_organization_id"
    t.index ["owner_id"], name: "index_prompt_templates_on_owner_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.integer "organization_id", null: false
    t.integer "user_id", null: false
    t.string "kind", null: false
    t.datetime "run_at", null: false
    t.string "state", default: "queued", null: false
    t.string "idempotency_key", null: false
    t.json "payload", default: {}
    t.string "channel", default: "in_app", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["idempotency_key"], name: "index_reminders_on_idempotency_key", unique: true
    t.index ["organization_id"], name: "index_reminders_on_organization_id"
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "survey_responses", force: :cascade do |t|
    t.integer "survey_id", null: false
    t.json "answers", default: {}
    t.string "respondent_label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["survey_id", "created_at"], name: "index_survey_responses_on_survey_id_and_created_at"
    t.index ["survey_id"], name: "index_survey_responses_on_survey_id"
  end

  create_table "surveys", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "title", null: false
    t.text "description"
    t.string "status", default: "draft", null: false
    t.json "questions", default: []
    t.integer "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id"], name: "index_surveys_on_campaign_id"
    t.index ["created_by_id"], name: "index_surveys_on_created_by_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "campaign_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "assignee_id"
    t.date "due_date"
    t.string "status", default: "open", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "priority"
    t.text "blocked_reason"
    t.integer "milestone_id"
    t.integer "depends_on_id"
    t.index ["assignee_id"], name: "index_tasks_on_assignee_id"
    t.index ["campaign_id"], name: "index_tasks_on_campaign_id"
    t.index ["depends_on_id"], name: "index_tasks_on_depends_on_id"
    t.index ["milestone_id"], name: "index_tasks_on_milestone_id"
    t.index ["priority"], name: "index_tasks_on_priority"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "locale"
    t.integer "reminder_lead_minutes", default: 1440, null: false
    t.string "reminder_channel", default: "in_app", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_calls", "organizations"
  add_foreign_key "ai_calls", "users"
  add_foreign_key "ai_runs", "artifacts", column: "output_artifact_id"
  add_foreign_key "ai_runs", "organizations"
  add_foreign_key "ai_runs", "users"
  add_foreign_key "approval_decisions", "approval_rounds"
  add_foreign_key "approval_decisions", "users"
  add_foreign_key "approval_rounds", "artifacts"
  add_foreign_key "approval_rounds", "users", column: "requester_id"
  add_foreign_key "approvals", "approval_rounds"
  add_foreign_key "approvals", "artifacts"
  add_foreign_key "approvals", "users"
  add_foreign_key "artifact_versions", "artifacts"
  add_foreign_key "artifact_versions", "users", column: "created_by_id"
  add_foreign_key "artifacts", "campaigns"
  add_foreign_key "artifacts", "users", column: "created_by_id"
  add_foreign_key "audit_logs", "organizations"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "campaign_collaborator_tokens", "campaigns"
  add_foreign_key "campaign_collaborator_tokens", "organizations"
  add_foreign_key "campaign_collaborator_tokens", "users", column: "invited_by_id"
  add_foreign_key "campaign_collaborators", "campaigns"
  add_foreign_key "campaign_collaborators", "users"
  add_foreign_key "campaigns", "clients"
  add_foreign_key "campaigns", "organizations"
  add_foreign_key "campaigns", "users", column: "owner_id"
  add_foreign_key "clients", "organizations"
  add_foreign_key "comments", "campaigns"
  add_foreign_key "comments", "users"
  add_foreign_key "event_attendees", "events"
  add_foreign_key "event_attendees", "users"
  add_foreign_key "events", "campaigns"
  add_foreign_key "facebook_authorizations", "organizations"
  add_foreign_key "facebook_authorizations", "users"
  add_foreign_key "facebook_page_connections", "organizations"
  add_foreign_key "facebook_page_connections", "users", column: "connected_by_id"
  add_foreign_key "facebook_posts", "artifacts"
  add_foreign_key "facebook_posts", "campaigns"
  add_foreign_key "facebook_posts", "facebook_page_connections"
  add_foreign_key "facebook_posts", "organizations"
  add_foreign_key "facebook_posts", "users", column: "approved_by_id"
  add_foreign_key "facebook_posts", "users", column: "created_by_id"
  add_foreign_key "facebook_publish_attempts", "facebook_posts"
  add_foreign_key "invitations", "organizations"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "milestones", "campaigns"
  add_foreign_key "milestones", "users", column: "owner_id"
  add_foreign_key "notifications", "organizations"
  add_foreign_key "notifications", "users"
  add_foreign_key "project_templates", "organizations"
  add_foreign_key "project_templates", "users", column: "owner_id"
  add_foreign_key "prompt_templates", "organizations"
  add_foreign_key "prompt_templates", "users", column: "owner_id"
  add_foreign_key "reminders", "organizations"
  add_foreign_key "reminders", "users"
  add_foreign_key "survey_responses", "surveys"
  add_foreign_key "surveys", "campaigns"
  add_foreign_key "surveys", "users", column: "created_by_id"
  add_foreign_key "tasks", "campaigns"
  add_foreign_key "tasks", "milestones"
  add_foreign_key "tasks", "tasks", column: "depends_on_id"
  add_foreign_key "tasks", "users", column: "assignee_id"
end
