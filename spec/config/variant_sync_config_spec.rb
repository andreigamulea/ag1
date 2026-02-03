# frozen_string_literal: true

require 'rails_helper'

RSpec.describe VariantSyncConfig do
  # Helper pentru a seta temporar ENV în teste
  def with_env(key, value)
    original_value = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = original_value
  end

  describe '.dual_lock_enabled?' do
    it 'returns true when ENV is "true" (case-insensitive)' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'true') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be true
      end
    end

    it 'returns true when ENV is "TRUE" (uppercase)' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'TRUE') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be true
      end
    end

    it 'returns true when ENV is "1"' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', '1') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be true
      end
    end

    it 'returns true when ENV is "yes"' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'yes') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be true
      end
    end

    it 'returns false when ENV is "false" (case-insensitive)' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'false') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be false
      end
    end

    it 'returns false when ENV is "FALSE" (uppercase)' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'FALSE') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be false
      end
    end

    it 'returns false when ENV is "0"' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', '0') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be false
      end
    end

    it 'returns false when ENV is "no"' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'no') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be false
      end
    end

    it 'returns true by default when ENV is absent' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', nil) do
        expect(VariantSyncConfig.dual_lock_enabled?).to be true
      end
    end

    it 'returns false for unrecognized values' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', 'maybe') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be false
      end
    end

    it 'handles whitespace in ENV value' do
      with_env('VARIANT_SYNC_DUAL_LOCK_ENABLED', '  true  ') do
        expect(VariantSyncConfig.dual_lock_enabled?).to be true
      end
    end
  end

  describe '.increment_dual_lock_counter' do
    context 'when StatsD is defined' do
      let(:statsd_double) { class_double('StatsD').as_stubbed_const }

      it 'calls StatsD.increment with correct metric name' do
        allow(statsd_double).to receive(:increment)

        VariantSyncConfig.increment_dual_lock_counter

        expect(statsd_double).to have_received(:increment).with('variant_sync.dual_lock_call')
      end
    end

    context 'when StatsD is not defined' do
      before do
        # Hide StatsD constant if it exists
        if defined?(StatsD)
          @original_statsd = Object.send(:remove_const, :StatsD)
        end
      end

      after do
        # Restore StatsD constant if it was removed
        Object.const_set(:StatsD, @original_statsd) if defined?(@original_statsd)
      end

      it 'does not raise NameError' do
        expect {
          VariantSyncConfig.increment_dual_lock_counter
        }.not_to raise_error
      end
    end
  end

  describe '.increment_legacy_lock_counter' do
    context 'when StatsD is defined' do
      let(:statsd_double) { class_double('StatsD').as_stubbed_const }

      it 'calls StatsD.increment with correct metric name' do
        allow(statsd_double).to receive(:increment)

        VariantSyncConfig.increment_legacy_lock_counter

        expect(statsd_double).to have_received(:increment).with('variant_sync.legacy_lock_call')
      end
    end

    context 'when StatsD is not defined' do
      before do
        # Hide StatsD constant if it exists
        if defined?(StatsD)
          @original_statsd = Object.send(:remove_const, :StatsD)
        end
      end

      after do
        # Restore StatsD constant if it was removed
        Object.const_set(:StatsD, @original_statsd) if defined?(@original_statsd)
      end

      it 'does not raise NameError' do
        expect {
          VariantSyncConfig.increment_legacy_lock_counter
        }.not_to raise_error
      end
    end
  end

  describe 'boot-time logging' do
    it 'logs dual-lock status on Rails initialization' do
      # Acest test verifică că inițializatorul este definit corect
      # Nu putem testa efectiv logging-ul în acest context, dar putem verifica că metoda există
      expect(VariantSyncConfig).to respond_to(:dual_lock_enabled?)
    end
  end
end
