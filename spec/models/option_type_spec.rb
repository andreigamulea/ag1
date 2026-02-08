require 'rails_helper'

RSpec.describe OptionType, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      option_type = build(:option_type)
      expect(option_type).to be_valid
    end

    it 'requires name' do
      option_type = build(:option_type, name: nil)
      expect(option_type).not_to be_valid
      expect(option_type.errors[:name]).to include("nu poate fi gol")
    end

    it 'requires unique name' do
      create(:option_type, name: 'Culoare')
      duplicate = build(:option_type, name: 'Culoare')
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('este deja folosit')
    end
  end

  describe 'associations' do
    it 'has many option_values' do
      option_type = create(:option_type)
      value1 = create(:option_value, option_type: option_type, name: 'Roșu')
      value2 = create(:option_value, option_type: option_type, name: 'Albastru')

      expect(option_type.option_values).to include(value1, value2)
    end

    it 'destroys option_values when destroyed' do
      option_type = create(:option_type)
      create(:option_value, option_type: option_type)

      expect { option_type.destroy }.to change(OptionValue, :count).by(-1)
    end
  end
end
