# frozen_string_literal: true

require 'zlib'

# app/services/variants/admin_external_id_service.rb
#
# Service pentru admin UI: link/unlink external IDs.
# DEADLOCK-SAFE: Foloseste acelasi advisory lock ca importul.
# Previne race conditions intre admin si import jobs.
#
# LOCK ORDER: A -> VEI (advisory lock, nu ia V lock)

module Variants
  class AdminExternalIdService
    include AdvisoryLockKey

    def initialize(variant)
      @variant = variant
    end

    # Link o varianta la un external ID
    # @return [Hash] { success:, action:, mapping:, error: }
    def link(source:, source_account: 'default', external_id:, external_sku: nil)
      normalized = VariantExternalId.normalize_lookup(
        source: source,
        external_id: external_id,
        source_account: source_account
      )

      return { success: false, error: "source obligatoriu" } if normalized[:source].blank?
      return { success: false, error: "external_id obligatoriu" } if normalized[:external_id].blank?

      VariantExternalId.transaction do
        acquire_external_id_lock(normalized[:source], normalized[:source_account], normalized[:external_id])

        existing = VariantExternalId.find_by(normalized)

        if existing
          if existing.variant_id == @variant.id
            return { success: true, action: :already_linked, mapping: existing }
          else
            return {
              success: false,
              error: "External ID deja folosit de varianta #{existing.variant_id}",
              action: :conflict
            }
          end
        end

        mapping = @variant.external_ids.create!(
          **normalized,
          external_sku: external_sku&.to_s&.strip.presence
        )

        { success: true, action: :linked, mapping: mapping }
      end
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.record.errors.full_messages.to_sentence }
    rescue ActiveRecord::RecordNotUnique
      { success: false, error: "External ID deja folosit", action: :conflict }
    end

    # Unlink un external ID de la varianta
    # @return [Hash] { success:, action:, error: }
    def unlink(source:, source_account: 'default', external_id:)
      normalized = VariantExternalId.normalize_lookup(
        source: source,
        external_id: external_id,
        source_account: source_account
      )

      VariantExternalId.transaction do
        acquire_external_id_lock(normalized[:source], normalized[:source_account], normalized[:external_id])

        mapping = @variant.external_ids.find_by(normalized)

        unless mapping
          return { success: false, error: "Mapping nu exista", action: :not_found }
        end

        mapping.destroy!
        { success: true, action: :unlinked }
      end
    end

    private

    # ROLLING DEPLOY SAFETY: Dual-lock (consistent cu VariantSyncService)
    def acquire_external_id_lock(source, source_account, external_id)
      return unless supports_pg_advisory_locks?

      assert_transaction_open_on_lock_connection!

      if VariantSyncConfig.dual_lock_enabled?
        acquire_external_id_lock_legacy(source, source_account, external_id)
        VariantSyncConfig.increment_dual_lock_counter
      end
      acquire_external_id_lock_v797(source, source_account, external_id)
    end

    # Legacy lock
    def acquire_external_id_lock_legacy(source, source_account, external_id)
      key = Zlib.crc32("#{source}|#{source_account}|#{external_id}")
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{key}::bigint)")
      VariantSyncConfig.increment_legacy_lock_counter
    end

    # New lock - int32() din AdvisoryLockKey concern
    def acquire_external_id_lock_v797(source, source_account, external_id)
      k1 = int32(Zlib.crc32("#{source}|#{source_account}"))
      k2 = int32(Zlib.crc32(external_id.to_s))
      advisory_lock_connection.execute("SELECT pg_advisory_xact_lock(#{k1}, #{k2})")
    end
  end
end
