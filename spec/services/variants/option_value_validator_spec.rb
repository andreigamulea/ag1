# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Variants::OptionValueValidator do
  # Creăm o clasă dummy pentru a testa concern-ul
  let(:dummy_class) do
    Class.new do
      include Variants::OptionValueValidator
    end
  end

  let(:instance) { dummy_class.new }

  describe '#valid_option_values_for_product?' do
    let(:product) { create(:product) }
    let(:option_type1) { create(:option_type, name: 'Culoare') }
    let(:option_type2) { create(:option_type, name: 'Mărime') }
    let(:option_value1) { create(:option_value, option_type: option_type1, name: 'Roșu') }
    let(:option_value2) { create(:option_value, option_type: option_type2, name: 'M') }

    before do
      # Asociem option_types cu produsul
      create(:product_option_type, product: product, option_type: option_type1)
      create(:product_option_type, product: product, option_type: option_type2)
    end

    it 'returns true when all option_values are valid' do
      expect(instance.valid_option_values_for_product?(product, [option_value1.id, option_value2.id])).to be true
    end

    it 'returns true for empty array' do
      expect(instance.valid_option_values_for_product?(product, [])).to be true
    end

    it 'returns false when an option_value ID does not exist' do
      non_existent_id = OptionValue.maximum(:id).to_i + 1
      expect(instance.valid_option_values_for_product?(product, [option_value1.id, non_existent_id])).to be false
    end

    it 'returns false when two option_values belong to the same option_type' do
      # Creăm a doua valoare din același option_type
      option_value1_alt = create(:option_value, option_type: option_type1, name: 'Albastru')

      expect(instance.valid_option_values_for_product?(product, [option_value1.id, option_value1_alt.id])).to be false
    end

    it 'returns false when option_type is not associated with the product' do
      # Creăm un option_type care NU e asociat cu produsul
      unassociated_type = create(:option_type, name: 'Material')
      unassociated_value = create(:option_value, option_type: unassociated_type, name: 'Bumbac')

      expect(instance.valid_option_values_for_product?(product, [option_value1.id, unassociated_value.id])).to be false
    end

    it 'returns true for single valid option_value' do
      expect(instance.valid_option_values_for_product?(product, [option_value1.id])).to be true
    end

    it 'handles product with no option_types associated' do
      product_no_options = create(:product)
      expect(instance.valid_option_values_for_product?(product_no_options, [option_value1.id])).to be false
    end
  end
end
