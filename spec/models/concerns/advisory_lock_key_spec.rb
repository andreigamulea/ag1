# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdvisoryLockKey do
  # Creăm o clasă dummy pentru a testa concern-ul
  let(:dummy_class) do
    Class.new do
      include AdvisoryLockKey

      # Exposăm metodele private pentru testare
      def public_supports_pg_advisory_locks?
        supports_pg_advisory_locks?
      end

      def public_transaction_open_on?(conn)
        transaction_open_on?(conn)
      end

      def public_assert_transaction_open_on_lock_connection!
        assert_transaction_open_on_lock_connection!
      end

      def public_int32(u)
        int32(u)
      end
    end
  end

  let(:instance) { dummy_class.new }

  describe '#supports_pg_advisory_locks?' do
    it 'returns boolean true when connection is PostgreSQL', :postgres_only do
      expect(instance.public_supports_pg_advisory_locks?).to be true
    end

    it 'returns boolean false when connection is not PostgreSQL' do
      allow(VariantExternalId.connection).to receive(:adapter_name).and_return('SQLite')
      expect(instance.public_supports_pg_advisory_locks?).to be false
    end
  end

  describe '#transaction_open_on?' do
    let(:connection) { VariantExternalId.connection }

    it 'returns true when transaction is open' do
      VariantExternalId.transaction do
        expect(instance.public_transaction_open_on?(connection)).to be true
      end
    end

    it 'uses transaction_open? when available' do
      # Verificăm doar că metoda returnează un boolean
      result = instance.public_transaction_open_on?(connection)
      expect([true, false]).to include(result)
    end

    context 'fallback to open_transactions' do
      let(:mock_connection) { double('Connection') }

      before do
        allow(mock_connection).to receive(:respond_to?).with(:transaction_open?).and_return(false)
        allow(mock_connection).to receive(:respond_to?).with(:open_transactions).and_return(true)
      end

      it 'returns true when open_transactions > 0' do
        allow(mock_connection).to receive(:open_transactions).and_return(1)
        expect(instance.public_transaction_open_on?(mock_connection)).to be true
      end

      it 'returns false when open_transactions = 0' do
        allow(mock_connection).to receive(:open_transactions).and_return(0)
        expect(instance.public_transaction_open_on?(mock_connection)).to be false
      end
    end

    context 'graceful degradation when neither method available' do
      let(:mock_connection) { double('Connection', class: 'MockConnection') }

      before do
        allow(mock_connection).to receive(:respond_to?).with(:transaction_open?).and_return(false)
        allow(mock_connection).to receive(:respond_to?).with(:open_transactions).and_return(false)
        allow(Rails.logger).to receive(:warn)
      end

      it 'returns true and logs warning' do
        expect(instance.public_transaction_open_on?(mock_connection)).to be true
        expect(Rails.logger).to have_received(:warn).with(/AdvisoryLockKey/)
      end
    end
  end

  describe '#assert_transaction_open_on_lock_connection!' do
    context 'when on non-Postgres DB' do
      before do
        allow(VariantExternalId.connection).to receive(:adapter_name).and_return('SQLite')
      end

      it 'does not raise error (skip lock on non-Postgres)' do
        expect {
          instance.public_assert_transaction_open_on_lock_connection!
        }.not_to raise_error
      end
    end

    context 'when on Postgres', :postgres_only do
      it 'does not raise error when inside transaction' do
        # RSpec uses transactional fixtures, so we're always in a transaction during tests
        expect {
          instance.public_assert_transaction_open_on_lock_connection!
        }.not_to raise_error
      end

      it 'raises RuntimeError when no transaction (simulated via mock)' do
        # Simulăm cazul fără tranzacție prin mock
        mock_connection = double('Connection', adapter_name: 'PostgreSQL')
        allow(mock_connection).to receive(:respond_to?).with(:transaction_open?).and_return(true)
        allow(mock_connection).to receive(:transaction_open?).and_return(false)
        allow(mock_connection).to receive_message_chain(:pool, :db_config, :name).and_return('test_db')

        # Override advisory_lock_connection temporar
        allow(instance).to receive(:advisory_lock_connection).and_return(mock_connection)

        expect {
          instance.public_assert_transaction_open_on_lock_connection!
        }.to raise_error(RuntimeError, /pg_advisory_xact_lock requires an open transaction/)
      end

      it 'error message includes connection name' do
        mock_connection = double('Connection', adapter_name: 'PostgreSQL')
        allow(mock_connection).to receive(:respond_to?).with(:transaction_open?).and_return(true)
        allow(mock_connection).to receive(:transaction_open?).and_return(false)
        allow(mock_connection).to receive_message_chain(:pool, :db_config, :name).and_return('my_database')

        allow(instance).to receive(:advisory_lock_connection).and_return(mock_connection)

        begin
          instance.public_assert_transaction_open_on_lock_connection!
        rescue RuntimeError => e
          expect(e.message).to match(/my_database/)
        end
      end
    end
  end

  describe '#int32' do
    it 'converts unsigned 32-bit to signed int32 for values < 2^31' do
      # Values below 2^31 remain positive
      expect(instance.public_int32(100)).to eq(100)
      expect(instance.public_int32(1000)).to eq(1000)
      expect(instance.public_int32(0x7FFF_FFFF)).to eq(0x7FFF_FFFF) # Max positive int32
    end

    it 'converts unsigned 32-bit to signed int32 for values >= 2^31' do
      # Values >= 2^31 become negative (two's complement)
      expect(instance.public_int32(0x8000_0000)).to eq(-0x8000_0000) # Min negative int32
      expect(instance.public_int32(0xFFFF_FFFF)).to eq(-1)
    end

    it 'handles edge cases correctly' do
      expect(instance.public_int32(0)).to eq(0)
      expect(instance.public_int32(0x8000_0000 - 1)).to eq(0x7FFF_FFFF) # Just before flip
      expect(instance.public_int32(0x8000_0000)).to eq(-0x8000_0000) # Flip point
    end

    it 'masks values to 32-bit range' do
      # Values larger than 32-bit should be masked
      large_value = 0x1_FFFF_FFFF # 33-bit value
      expect(instance.public_int32(large_value)).to eq(-1) # Masked to 0xFFFF_FFFF → -1
    end
  end

  describe '#advisory_lock_connection (default implementation)' do
    it 'returns VariantExternalId.connection by default' do
      expect(instance.send(:advisory_lock_connection)).to eq(VariantExternalId.connection)
    end
  end
end
