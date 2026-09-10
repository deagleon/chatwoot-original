# Enable captain features for all existing accounts.
# Mirrors 20260120121402_enable_captain_tasks_for_existing_accounts.rb.
# ACCOUNT_LEVEL_FEATURE_DEFAULTS is updated explicitly below because ConfigLoader
# runs with reconcile_only_new: true and keeps stale `enabled: false` entries
# for flags that already exist in the config.
class EnableCaptainFeaturesForAllAccounts < ActiveRecord::Migration[7.0]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each do |account|
        features = %w[captain_integration captain_document_auto_sync custom_tools]
        # Accounts explicitly locked to Captain V1 keep the legacy behaviour
        features << 'captain_integration_v2' unless account.internal_attributes['captain_v2_default_eligible'] == false
        account.enable_features!(*features)
      end
    end

    # New accounts on existing installs read ACCOUNT_LEVEL_FEATURE_DEFAULTS.
    # Update the captain entries so they default to enabled (pattern from
    # 20260324102005_repurpose_response_bot_flag_for_custom_tools.rb).
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    captain_features = %w[captain_integration captain_integration_v2 captain_document_auto_sync custom_tools]
    config.value = config.value.map do |feature|
      captain_features.include?(feature['name']) ? feature.merge('enabled' => true) : feature
    end
    config.save!
    GlobalConfig.clear_cache
  end
end
