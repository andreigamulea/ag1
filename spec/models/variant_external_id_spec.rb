require 'rails_helper'

RSpec.describe VariantExternalId, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      vei = build(:variant_external_id)
      expect(vei).to be_valid
    end

    it 'requires source' do
      vei = build(:variant_external_id, source: nil)
      expect(vei).not_to be_valid
      expect(vei.errors[:source]).to include("can't be blank")
    end

    it 'requires external_id' do
      vei = build(:variant_external_id, external_id: nil)
      expect(vei).not_to be_valid
      expect(vei.errors[:external_id]).to include("can't be blank")
    end

    it 'requires source to be lowercase' do
      vei = build(:variant_external_id, source: 'EMAG')
      # Normalizarea ar trebui să îl facă valid
      expect(vei).to be_valid
      expect(vei.source).to eq('emag')
    end

    it 'rejects invalid source format' do
      vei = build(:variant_external_id, source: '123invalid')
      expect(vei).not_to be_valid
    end

    it 'requires unique external_id per source and account' do
      variant1 = create(:variant)
      variant2 = create(:variant)

      create(:variant_external_id,
             variant: variant1,
             source: 'erp',
             source_account: 'default',
             external_id: 'ERP-001')

      duplicate = build(:variant_external_id,
                        variant: variant2,
                        source: 'erp',
                        source_account: 'default',
                        external_id: 'ERP-001')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to include('has already been taken')
    end

    it 'allows same external_id on different source_accounts' do
      variant1 = create(:variant)
      variant2 = create(:variant)

      create(:variant_external_id,
             variant: variant1,
             source: 'emag',
             source_account: 'emag_ro_1',
             external_id: '12345')

      vei2 = build(:variant_external_id,
                   variant: variant2,
                   source: 'emag',
                   source_account: 'emag_ro_2',
                   external_id: '12345')

      expect(vei2).to be_valid
    end
  end

  describe 'normalization' do
    it 'normalizes source to lowercase' do
      vei = build(:variant_external_id, source: 'EMAG')
      vei.valid?
      expect(vei.source).to eq('emag')
    end

    it 'normalizes source_account to lowercase' do
      vei = build(:variant_external_id, source_account: 'EMAG_RO_1')
      vei.valid?
      expect(vei.source_account).to eq('emag_ro_1')
    end

    it 'strips whitespace from external_id' do
      vei = build(:variant_external_id, external_id: '  EXT-123  ')
      vei.valid?
      expect(vei.external_id).to eq('EXT-123')
    end
  end

  describe '.find_variant' do
    it 'finds variant by external_id' do
      variant = create(:variant)
      create(:variant_external_id,
             variant: variant,
             source: 'erp',
             source_account: 'default',
             external_id: 'ERP-001')

      found = VariantExternalId.find_variant(source: 'erp', external_id: 'ERP-001')
      expect(found).to eq(variant)
    end

    it 'returns nil when not found' do
      found = VariantExternalId.find_variant(source: 'erp', external_id: 'NONEXISTENT')
      expect(found).to be_nil
    end

    it 'respects source_account parameter' do
      variant1 = create(:variant)
      variant2 = create(:variant)

      create(:variant_external_id,
             variant: variant1,
             source: 'emag',
             source_account: 'emag_ro_1',
             external_id: '123')

      create(:variant_external_id,
             variant: variant2,
             source: 'emag',
             source_account: 'emag_ro_2',
             external_id: '123')

      found1 = VariantExternalId.find_variant(source: 'emag', external_id: '123', source_account: 'emag_ro_1')
      found2 = VariantExternalId.find_variant(source: 'emag', external_id: '123', source_account: 'emag_ro_2')

      expect(found1).to eq(variant1)
      expect(found2).to eq(variant2)
    end
  end

  describe 'scopes' do
    before do
      @variant = create(:variant)
      @vei_erp = create(:variant_external_id, variant: @variant, source: 'erp', source_account: 'default')
      @vei_emag1 = create(:variant_external_id, variant: @variant, source: 'emag', source_account: 'emag_ro_1')
      @vei_emag2 = create(:variant_external_id, variant: @variant, source: 'emag', source_account: 'emag_ro_2')
    end

    it 'by_source returns records for source' do
      results = VariantExternalId.by_source('emag')
      expect(results).to include(@vei_emag1, @vei_emag2)
      expect(results).not_to include(@vei_erp)
    end

    it 'by_source_account returns records for source and account' do
      results = VariantExternalId.by_source_account('emag', 'emag_ro_1')
      expect(results).to include(@vei_emag1)
      expect(results).not_to include(@vei_emag2, @vei_erp)
    end
  end

  describe '.normalize_lookup' do
    it 'normalizes source to lowercase and stripped' do
      result = VariantExternalId.normalize_lookup(source: '  ERP  ', external_id: 'X1')
      expect(result[:source]).to eq('erp')
    end

    it 'normalizes source_account to lowercase with default fallback' do
      result = VariantExternalId.normalize_lookup(source: 'erp', external_id: 'X1', source_account: nil)
      expect(result[:source_account]).to eq('default')

      result2 = VariantExternalId.normalize_lookup(source: 'erp', external_id: 'X1', source_account: '  ')
      expect(result2[:source_account]).to eq('default')

      result3 = VariantExternalId.normalize_lookup(source: 'erp', external_id: 'X1', source_account: ' EMAG_RO ')
      expect(result3[:source_account]).to eq('emag_ro')
    end

    it 'strips whitespace from external_id' do
      result = VariantExternalId.normalize_lookup(source: 'erp', external_id: '  EXT-123  ')
      expect(result[:external_id]).to eq('EXT-123')
    end

    it 'handles nil/blank inputs via compact' do
      result = VariantExternalId.normalize_lookup(source: '', external_id: '')
      # source and external_id are nil after .presence, so compact removes them
      expect(result).not_to have_key(:source)
      expect(result).not_to have_key(:external_id)
      expect(result[:source_account]).to eq('default')
    end
  end

  describe 'associations' do
    it 'is destroyed when variant is destroyed' do
      variant = create(:variant)
      create(:variant_external_id, variant: variant)

      expect { variant.destroy }.to change(VariantExternalId, :count).by(-1)
    end
  end
end
