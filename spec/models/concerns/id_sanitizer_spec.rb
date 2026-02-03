# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IdSanitizer do
  # Creăm o clasă dummy pentru a testa concern-ul
  let(:dummy_class) do
    Class.new do
      include IdSanitizer
    end
  end

  let(:instance) { dummy_class.new }

  describe '.sanitize_ids (class method)' do
    it 'converts valid string IDs to integers' do
      expect(dummy_class.sanitize_ids(['1', '2', '3'])).to eq([1, 2, 3])
    end

    it 'accepts Integer input directly' do
      expect(dummy_class.sanitize_ids([1, 2, 3])).to eq([1, 2, 3])
    end

    it 'handles mixed String and Integer input' do
      expect(dummy_class.sanitize_ids(['1', 2, '3'])).to eq([1, 2, 3])
    end

    it 'drops nil values without error' do
      expect(dummy_class.sanitize_ids([1, nil, 2])).to eq([1, 2])
    end

    it 'drops empty string without error' do
      expect(dummy_class.sanitize_ids(['1', '', '2'])).to eq([1, 2])
    end

    it 'drops whitespace-only string without error (CONTRACT: whitespace→drop)' do
      expect(dummy_class.sanitize_ids(['1', '  ', '2'])).to eq([1, 2])
      expect(dummy_class.sanitize_ids([' '])).to eq([])
    end

    it 'returns unique sorted IDs' do
      expect(dummy_class.sanitize_ids([3, 1, 2, 1])).to eq([1, 2, 3])
    end

    it 'handles empty array' do
      expect(dummy_class.sanitize_ids([])).to eq([])
    end

    it 'handles nil input' do
      expect(dummy_class.sanitize_ids(nil)).to eq([])
    end

    it 'raises ArgumentError for zero' do
      expect {
        dummy_class.sanitize_ids([0])
      }.to raise_error(ArgumentError, /ID must be positive integer/)
    end

    it 'raises ArgumentError for negative numbers' do
      expect {
        dummy_class.sanitize_ids([-1])
      }.to raise_error(ArgumentError, /ID must be positive integer/)
    end

    it 'raises ArgumentError for non-numeric strings' do
      expect {
        dummy_class.sanitize_ids(['abc'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end

    it 'raises ArgumentError for decimal strings' do
      expect {
        dummy_class.sanitize_ids(['1.5'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end

    it 'raises ArgumentError for hex format (STRICT DECIMAL)' do
      expect {
        dummy_class.sanitize_ids(['0x10'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end

    it 'raises ArgumentError for octal format (STRICT DECIMAL)' do
      expect {
        dummy_class.sanitize_ids(['0o17'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end

    it 'raises ArgumentError for binary format (STRICT DECIMAL)' do
      expect {
        dummy_class.sanitize_ids(['0b101'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end

    it 'raises ArgumentError for underscore separator (STRICT DECIMAL)' do
      expect {
        dummy_class.sanitize_ids(['1_000'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end

    it 'raises ArgumentError for leading zero (STRICT DECIMAL)' do
      expect {
        dummy_class.sanitize_ids(['01'])
      }.to raise_error(ArgumentError, /ID must be decimal digits only/)
    end
  end

  describe '#sanitize_ids (instance method)' do
    it 'delegates to class method (SINGLE-SOURCE pattern)' do
      # Test că instance method apelează class method
      expect(dummy_class).to receive(:sanitize_ids).with([1, 2, 3])
      instance.send(:sanitize_ids, [1, 2, 3])
    end

    it 'produces same result as class method' do
      input = ['3', 1, '2', nil, ' ']
      expect(instance.send(:sanitize_ids, input)).to eq(dummy_class.sanitize_ids(input))
    end
  end
end
