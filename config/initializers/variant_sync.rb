# frozen_string_literal: true

# config/initializers/variant_sync.rb
#
# Feature flags și observability pentru Imports::VariantSyncService
#
# DUAL-LOCK DEPRECATION STRATEGY:
# - ENV['VARIANT_SYNC_DUAL_LOCK_ENABLED'] = "true" (default) → acquire both legacy + new advisory locks
# - ENV['VARIANT_SYNC_DUAL_LOCK_ENABLED'] = "false" → acquire only new advisory lock
#
# Counters permit tracking volumului de apeluri pentru a determina când e safe să dezactivăm dual-lock.

module VariantSyncConfig
  # Citește ENV și convertește la boolean
  # CASE-INSENSITIVE: "true", "TRUE", "1", "yes" → true
  # CASE-INSENSITIVE: "false", "FALSE", "0", "no" → false
  # DEFAULT: true (dual-lock activat pentru backward compatibility)
  def self.dual_lock_enabled?
    value = ENV.fetch('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'true').to_s.strip.downcase
    %w[true 1 yes].include?(value)
  end

  # FIX 8.5: Guard `defined?(StatsD)` pentru a preveni NameError când StatsD nu e în Gemfile
  # Incrementează counter pentru număr de apeluri cu dual-lock activat
  def self.increment_dual_lock_counter
    StatsD.increment('variant_sync.dual_lock_call') if defined?(StatsD)
  end

  # Incrementează counter pentru număr de apeluri care folosesc legacy lock format
  # Folosit pentru a determina când e safe să dezactivăm dual-lock (când counter → 0)
  def self.increment_legacy_lock_counter
    StatsD.increment('variant_sync.legacy_lock_call') if defined?(StatsD)
  end
end

# Boot-time logging pentru status dual-lock (debugging + observability)
Rails.application.config.after_initialize do
  status = VariantSyncConfig.dual_lock_enabled? ? "ENABLED" : "DISABLED"
  Rails.logger.info("[VariantSyncConfig] Dual-lock strategy: #{status}")
end
