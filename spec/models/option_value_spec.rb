require 'rails_helper'

RSpec.describe OptionValue, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      option_value = build(:option_value)
      expect(option_value).to be_valid
    end

    it 'requires name' do
      option_value = build(:option_value, name: nil)
      expect(option_value).not_to be_valid
      expect(option_value.errors[:name]).to include("nu poate fi gol")
    end

    it 'requires unique name within option_type' do
      option_type = create(:option_type)
      create(:option_value, option_type: option_type, name: 'Roșu')
      duplicate = build(:option_value, option_type: option_type, name: 'Roșu')

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('este deja folosit')
    end

    it 'allows same name in different option_types' do
      type1 = create(:option_type, name: 'Culoare')
      type2 = create(:option_type, name: 'Material')

      create(:option_value, option_type: type1, name: 'Negru')
      value2 = build(:option_value, option_type: type2, name: 'Negru')

      expect(value2).to be_valid
    end
  end

  describe '#display_name' do
    it 'returns presentation if set' do
      option_value = build(:option_value, name: 'red', presentation: 'Roșu')
      expect(option_value.display_name).to eq('Roșu')
    end

    it 'returns name if presentation is blank' do
      option_value = build(:option_value, name: 'Roșu', presentation: nil)
      expect(option_value.display_name).to eq('Roșu')
    end
  end
end
