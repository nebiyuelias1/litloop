module BooksHelper
  # Book#language is free text: mostly BCP 47 codes ("am", "en", "zh-CN"),
  # with some legacy names ("English", "Multiple languages").
  LANGUAGE_CODE = /\A[a-z]{2,3}(-[A-Za-z]{2,4})?\z/

  # A valid `lang` attribute value for the book's own text, or nil when the
  # stored language isn't a code (the page language then applies).
  def book_lang_attribute(book)
    code = book.language.to_s.strip
    code if code.match?(LANGUAGE_CODE)
  end

  # Human-readable language name in the reader's locale; falls back to the
  # stored value so unknown codes and legacy names still display.
  def book_language_name(book)
    value = book.language.to_s.strip
    return if value.blank?

    t("languages.#{value}", default: value)
  end
end
