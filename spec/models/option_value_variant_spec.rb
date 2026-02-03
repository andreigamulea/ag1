require 'rails_helper'

RSpec.describe OptionValueVariant, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      ovv = build(:option_value_variant)
      expect(ovv).to be_valid
    end

    it 'requires unique option_value per variant' do
      variant = create(:variant)
      option_value = create(:option_value)

      create(:option_value_variant, variant: variant, option_value: option_value)
      duplicate = build(:option_value_variant, variant: variant, option_value: option_value)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:option_value_id]).to include('has already been taken')
    end

    it 'allows same option_value on different variants' do
      option_value = create(:option_value)
      variant1 = create(:variant)
      variant2 = create(:variant)

      create(:option_value_variant, variant: variant1, option_value: option_value)
      ovv2 = build(:option_value_variant, variant: variant2, option_value: option_value)

      expect(ovv2).to be_valid
    end
  end
end
