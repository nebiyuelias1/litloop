class DiscussionQuestion < ApplicationRecord
  belongs_to :book_read
  belongs_to :user, optional: true
  has_many :question_translations, dependent: :destroy

  # Use ZH-HANT for Traditional Chinese in DeepL, and ZH for Simplified
  TARGET_LANGUAGES = [ "ZH-HANT" ].freeze

  enum :status, { draft: 0, approved: 1, revealed: 2 }, default: :draft

  validates :content, presence: true
  validates :position, uniqueness: { scope: :book_read_id }

  before_save :set_edited_flag, if: :will_save_change_to_content?
  before_create :set_position
  after_commit :translate_content, on: [ :create, :update ]
  after_create_commit :broadcast_create
  after_update_commit :broadcast_update
  after_destroy_commit :broadcast_destroy

  def content_for_language(lang_code)
    lang_code = lang_code.to_s.upcase

    if lang_code.match?(/^ZH-(TW|HK|MO|HANT)/)
      lang_code = "ZH-HANT" # Traditional
    elsif lang_code.start_with?("ZH")
      lang_code = "ZH" # Simplified
    end

    return content if lang_code.start_with?("EN") || lang_code.blank?

    translation = question_translations.find_by(language_code: lang_code)
    translation ? translation.content : content
  end

  private

  def set_edited_flag
    self.edited = true unless new_record?
  end

  def translate_content
    if saved_change_to_content?
      TARGET_LANGUAGES.each do |lang_code|
        TranslateDiscussionQuestionJob.perform_later(id, lang_code)
      end
    end
  end

  def broadcast_create
    broadcast_append_to [ book_read, :discussion_questions ], target: "discussion_questions_list"
    broadcast_remove_to [ book_read, :discussion_questions ], target: "no_discussion_questions"
    broadcast_counts
  end

  def broadcast_update
    broadcast_replace_to [ book_read, :discussion_questions ]
  end

  def broadcast_destroy
    broadcast_remove_to [ book_read, :discussion_questions ]
    broadcast_counts
  end

  def broadcast_counts
    count = book_read.discussion_questions.count
    %w[discussion_questions_count discussion_questions_nav_count].each do |dom_id|
      broadcast_replace_to [ book_read, :discussion_questions ],
        target: dom_id,
        partial: "discussion_questions/count",
        locals: { id: dom_id, count: count }
    end
  end

  def set_position
    book_read.with_lock do
      max_position = book_read.discussion_questions.maximum(:position) || 0
      self.position = max_position + 1
    end
  end
end
