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

ActiveRecord::Schema[8.0].define(version: 2026_11_10_154413) do
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

  create_table "book_club_members", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_club_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_club_id"], name: "index_book_club_members_on_book_club_id"
    t.index ["user_id", "book_club_id"], name: "index_book_club_members_on_user_id_and_book_club_id", unique: true
    t.index ["user_id"], name: "index_book_club_members_on_user_id"
  end

  create_table "book_clubs", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.boolean "is_private", default: false
    t.integer "owner_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "book_club_members_count", default: 0, null: false
    t.string "application_form_url"
    t.json "literature_dna"
    t.datetime "dna_generated_at"
    t.index ["owner_id"], name: "index_book_clubs_on_owner_id"
  end

  create_table "book_read_rsvps", force: :cascade do |t|
    t.integer "book_read_id", null: false
    t.integer "user_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "reminder_sent_at"
    t.datetime "reminder_claimed_at"
    t.index ["book_read_id", "user_id"], name: "index_book_read_rsvps_on_book_read_id_and_user_id", unique: true
    t.index ["book_read_id"], name: "index_book_read_rsvps_on_book_read_id"
    t.index ["user_id"], name: "index_book_read_rsvps_on_user_id"
  end

  create_table "book_reads", force: :cascade do |t|
    t.integer "book_id"
    t.integer "book_club_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "meetup_location"
    t.datetime "meetup_time"
    t.integer "max_capacity"
    t.integer "host_id", null: false
    t.integer "calendar_sequence", default: 0, null: false
    t.index ["book_club_id"], name: "index_book_reads_on_book_club_id"
    t.index ["book_id"], name: "index_book_reads_on_book_id"
    t.index ["host_id"], name: "index_book_reads_on_host_id"
    t.check_constraint "max_capacity IS NULL OR max_capacity >= 2", name: "book_reads_max_capacity_min"
  end

  create_table "book_tags", force: :cascade do |t|
    t.integer "book_id", null: false
    t.integer "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id", "tag_id"], name: "index_book_tags_on_book_id_and_tag_id", unique: true
    t.index ["book_id"], name: "index_book_tags_on_book_id"
    t.index ["tag_id"], name: "index_book_tags_on_tag_id"
  end

  create_table "books", force: :cascade do |t|
    t.string "title", null: false
    t.string "author"
    t.text "description"
    t.date "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "language", default: "am"
    t.string "cover_image"
    t.string "publisher"
    t.string "isbn"
    t.float "average_rating", default: 0.0, null: false
    t.integer "reviews_count", default: 0, null: false
    t.string "telegram_post_id"
    t.string "source"
    t.string "source_url"
    t.string "title_en"
    t.string "title_romanized"
    t.string "author_romanized"
    t.integer "page_count"
    t.string "country_of_origin"
    t.datetime "enriched_at"
    t.json "enrichment"
  end

  create_table "discussion_questions", force: :cascade do |t|
    t.integer "book_read_id", null: false
    t.integer "status", default: 0, null: false
    t.text "content", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "edited"
    t.index ["book_read_id"], name: "index_discussion_questions_on_book_read_id"
    t.index ["user_id"], name: "index_discussion_questions_on_user_id"
  end

  create_table "membership_requests", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_club_id", null: false
    t.integer "status", default: 0, null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_club_id"], name: "index_membership_requests_on_book_club_id"
    t.index ["user_id", "book_club_id"], name: "index_membership_requests_on_user_id_and_book_club_id", unique: true
    t.index ["user_id"], name: "index_membership_requests_on_user_id"
  end

  create_table "poll_options", force: :cascade do |t|
    t.integer "poll_id", null: false
    t.string "content", null: false
    t.integer "book_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "suggested_by_id"
    t.index ["book_id"], name: "index_poll_options_on_book_id"
    t.index ["poll_id"], name: "index_poll_options_on_poll_id"
    t.index ["suggested_by_id"], name: "index_poll_options_on_suggested_by_id"
  end

  create_table "poll_votes", force: :cascade do |t|
    t.integer "poll_option_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["poll_option_id", "user_id"], name: "index_poll_votes_on_poll_option_id_and_user_id", unique: true
    t.index ["poll_option_id"], name: "index_poll_votes_on_poll_option_id"
    t.index ["user_id"], name: "index_poll_votes_on_user_id"
  end

  create_table "polls", force: :cascade do |t|
    t.integer "book_read_id", null: false
    t.string "text", null: false
    t.text "description"
    t.datetime "end_date", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "finalized_at"
    t.integer "selected_poll_option_id"
    t.index ["book_read_id"], name: "index_polls_on_book_read_id"
    t.index ["selected_poll_option_id"], name: "index_polls_on_selected_poll_option_id"
  end

  create_table "question_translations", force: :cascade do |t|
    t.integer "discussion_question_id", null: false
    t.string "language_code", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["discussion_question_id", "language_code"], name: "index_question_translations_on_question_and_lang", unique: true
    t.index ["discussion_question_id"], name: "index_question_translations_on_discussion_question_id"
  end

  create_table "ratings", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "book_id", null: false
    t.float "score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_ratings_on_book_id"
    t.index ["user_id"], name: "index_ratings_on_user_id"
  end

  create_table "review_likes", force: :cascade do |t|
    t.integer "review_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["review_id", "user_id"], name: "index_review_likes_on_review_id_and_user_id", unique: true
    t.index ["review_id"], name: "index_review_likes_on_review_id"
    t.index ["user_id"], name: "index_review_likes_on_user_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.text "body"
    t.integer "book_id", null: false
    t.integer "user_id", null: false
    t.integer "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "review_likes_count", default: 0, null: false
    t.index ["book_id"], name: "index_reviews_on_book_id"
    t.index ["parent_id"], name: "index_reviews_on_parent_id"
    t.index ["user_id"], name: "index_reviews_on_user_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "telegram_id"
    t.string "name"
    t.string "username"
    t.string "line_id"
    t.boolean "admin", default: false, null: false
    t.string "avatar_url"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["line_id"], name: "index_users_on_line_id", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "book_club_members", "book_clubs"
  add_foreign_key "book_club_members", "users"
  add_foreign_key "book_clubs", "users", column: "owner_id"
  add_foreign_key "book_read_rsvps", "book_reads"
  add_foreign_key "book_read_rsvps", "users"
  add_foreign_key "book_reads", "book_clubs"
  add_foreign_key "book_reads", "books"
  add_foreign_key "book_reads", "users", column: "host_id"
  add_foreign_key "book_tags", "books"
  add_foreign_key "book_tags", "tags"
  add_foreign_key "discussion_questions", "book_reads"
  add_foreign_key "discussion_questions", "users"
  add_foreign_key "membership_requests", "book_clubs"
  add_foreign_key "membership_requests", "users"
  add_foreign_key "poll_options", "books"
  add_foreign_key "poll_options", "polls"
  add_foreign_key "poll_options", "users", column: "suggested_by_id"
  add_foreign_key "poll_votes", "poll_options"
  add_foreign_key "poll_votes", "users"
  add_foreign_key "polls", "book_reads"
  add_foreign_key "polls", "poll_options", column: "selected_poll_option_id"
  add_foreign_key "question_translations", "discussion_questions"
  add_foreign_key "ratings", "books"
  add_foreign_key "ratings", "users"
  add_foreign_key "review_likes", "reviews"
  add_foreign_key "review_likes", "users"
  add_foreign_key "reviews", "books"
  add_foreign_key "reviews", "reviews", column: "parent_id"
  add_foreign_key "reviews", "users"

  # Virtual tables defined in this database.
  # Note that virtual tables may not work with other database engines. Be careful if changing database.
  create_virtual_table "books_fts", "fts5", ["title", "author", "description", "publisher", "title_en", "title_romanized", "author_romanized", "content=books", "content_rowid=id"]
end
