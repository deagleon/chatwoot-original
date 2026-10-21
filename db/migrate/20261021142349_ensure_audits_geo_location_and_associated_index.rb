# Production recorded 20260813000000 and 20260814000000 from the fork's Trello/Captain migrations,
# so the upstream audits migrations with the same versions never ran there.
# This re-applies them idempotently: AddGeoLocationToAudits and AddAssociatedCreatedAtIndexToAudits.
class EnsureAuditsGeoLocationAndAssociatedIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_column :audits, :city, :string, if_not_exists: true
    add_column :audits, :country, :string, if_not_exists: true
    add_column :audits, :country_code, :string, if_not_exists: true

    add_index :audits, [:associated_type, :associated_id, :created_at],
              name: 'index_audits_on_associated_and_created_at',
              algorithm: :concurrently,
              if_not_exists: true
  end

  # The objects belong to the upstream migrations; rolling this one back must not drop them.
  def down; end
end
