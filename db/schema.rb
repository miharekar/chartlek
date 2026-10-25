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

ActiveRecord::Schema[8.1].define(version: 2026_10_25_091117) do
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
    t.float "spi"
    t.float "vdot"
    t.string "location_name"
    t.json "summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
end
