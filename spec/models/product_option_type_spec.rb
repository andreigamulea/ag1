require 'rails_helper'

RSpec.describe ProductOptionType, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      pot = build(:product_option_type)
      expect(pot).to be_valid
    end

    it 'requires unique option_type per product' do
      product = create(:product)
      option_type = create(:option_type)

      create(:product_option_type, product: product, option_type: option_type)
      duplicate = build(:product_option_type, product: product, option_type: option_type)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:option_type_id]).to include('has already been taken')
    end

    it 'allows same option_type on different products' do
      option_type = create(:option_type)
      product1 = create(:product)
      product2 = create(:product)

      create(:product_option_type, product: product1, option_type: option_type)
      pot2 = build(:product_option_type, product: product2, option_type: option_type)

      expect(pot2).to be_valid
    end
  end
end
