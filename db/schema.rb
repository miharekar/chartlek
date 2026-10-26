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

ActiveRecord::Schema[8.1].define(version: 2026_10_26_090000) do
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

  create_table "activities", force: :cascade do |t|
    t.string "source", null: false
    t.string "external_id", null: false
    t.datetime "started_at", null: false
    t.datetime "local_started_at", null: false
    t.string "name"
    t.string "activity_type", null: false
    t.boolean "indoor", default: false, null: false
    t.boolean "race", default: false, null: false
    t.float "distance_m", null: false
    t.float "timer_s", null: false
    t.float "moving_s"
    t.float "elapsed_s"
    t.float "elevation_gain_m"
    t.float "elevation_loss_m"
    t.integer "avg_hr"
    t.integer "max_hr"
    t.integer "calories"
    t.float "avg_cadence"
    t.float "max_cadence"
    t.float "vo2max"
    t.float "start_lat"
    t.float "start_lng"
    t.float "vdot"
    t.string "location_name"
    t.json "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "splits"
    t.json "pace_profile"
    t.float "pace_variability"
    t.json "weather"
    t.index ["local_started_at"], name: "index_activities_on_local_started_at"
    t.index ["source", "external_id"], name: "index_activities_on_source_and_external_id", unique: true
  end

  create_table "profiles", force: :cascade do |t|
    t.json "settings"
    t.datetime "synced_at"
    t.datetime "sync_started_at"
    t.text "sync_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tracks", force: :cascade do |t|
    t.integer "activity_id", null: false
    t.json "data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["activity_id"], name: "index_tracks_on_activity_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "tracks", "activities"
end
