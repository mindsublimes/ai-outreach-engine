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

ActiveRecord::Schema[8.0].define(version: 2026_03_16_062239) do
  create_table "outreach_drafts", force: :cascade do |t|
    t.integer "prospect_id", null: false
    t.string "subject", null: false
    t.text "body", null: false
    t.string "status", default: "draft", null: false
    t.string "gmail_thread_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["gmail_thread_id"], name: "index_outreach_drafts_on_gmail_thread_id"
    t.index ["prospect_id"], name: "index_outreach_drafts_on_prospect_id"
    t.index ["status"], name: "index_outreach_drafts_on_status"
  end

  create_table "prospects", force: :cascade do |t|
    t.string "url", null: false
    t.string "b2b_b2c_status", default: "unknown", null: false
    t.text "research_summary"
    t.string "company_name"
    t.string "track", default: "partner"
    t.string "category"
    t.string "email"
    t.string "status", default: "pending", null: false
    t.boolean "is_b2b"
    t.text "observation"
    t.string "target_persona"
    t.boolean "research_failed", default: false, null: false
    t.text "failure_reason"
    t.text "generated_email_body"
    t.string "first_name"
    t.string "last_name"
    t.string "job_title"
    t.string "generated_email_subject"
    t.string "business_type"
    t.decimal "look_alike_score", precision: 3, scale: 2
    t.boolean "owner_operator_match"
    t.string "priority"
    t.boolean "is_scalable", default: false
    t.text "signals_detected"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "accept_category"
    t.index ["b2b_b2c_status"], name: "index_prospects_on_b2b_b2c_status"
    t.index ["is_scalable"], name: "index_prospects_on_is_scalable"
    t.index ["track"], name: "index_prospects_on_track"
    t.index ["url"], name: "index_prospects_on_url", unique: true
  end

  create_table "reference_partners", force: :cascade do |t|
    t.string "url", null: false
    t.string "name"
    t.text "about_summary"
    t.text "products_summary"
    t.text "owner_operator_indicators"
    t.integer "display_order", default: 0, null: false
    t.datetime "last_scraped_at"
    t.string "domain"
    t.string "category"
    t.text "dna_signals"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "perks_url"
    t.index ["category"], name: "index_reference_partners_on_category"
    t.index ["display_order"], name: "index_reference_partners_on_display_order"
    t.index ["domain"], name: "index_reference_partners_on_domain"
    t.index ["url"], name: "index_reference_partners_on_url", unique: true
  end

  add_foreign_key "outreach_drafts", "prospects"
end
