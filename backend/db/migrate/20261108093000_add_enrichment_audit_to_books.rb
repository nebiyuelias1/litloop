class AddEnrichmentAuditToBooks < ActiveRecord::Migration[8.0]
  def change
    add_column :books, :enrichment, :json
  end
end
