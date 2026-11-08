# Converts country names stored by earlier enrichment runs into ISO 3166-1
# alpha-2 codes (e.g. "Nigeria" -> "NG"). Unmappable values are cleared.
class MigrateCountryNamesToIsoCodes < ActiveRecord::Migration[8.0]
  def up
    Book.where.not(country_of_origin: nil).find_each do |book|
      code = CountryCodes.code_for(book.country_of_origin)
      book.update_columns(country_of_origin: code) if code != book.country_of_origin
    end
  end

  def down
    # Original names live on in book.enrichment["applied_country_of_origin"] history — not reversible
  end
end
