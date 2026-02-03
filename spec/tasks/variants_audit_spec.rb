# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe "variants:audit rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('variants:audit')
  end

  before do
    Rake::Task['variants:audit'].reenable
  end

  it 'runs without errors on clean DB' do
    output = capture_stdout { Rake::Task['variants:audit'].invoke }
    expect(output).to include("=== VARIANTS AUDIT ===")
    expect(output).to include("=== END AUDIT ===")
    expect(output).to include("No SKU duplicates")
    expect(output).to include("No negative stock")
    expect(output).to include("No negative price")
  end

  it 'reports variant counts correctly' do
    product = create(:product)
    create(:variant, product: product, sku: 'AUDIT-V1', stock: 10, price: 20.0)

    output = capture_stdout { Rake::Task['variants:audit'].invoke }
    expect(output).to include("No SKU duplicates")
    expect(output).to include("No negative stock")
    expect(output).to include("No negative price")
    expect(output).to include("No NULL stock")
    expect(output).to include("No NULL price")
  end

  it 'reports external ID stats when variant_external_ids table exists' do
    product = create(:product)
    variant = create(:variant, product: product, sku: 'AUDIT-EXT')
    create(:variant_external_id, variant: variant, source: 'erp', external_id: 'E1')

    output = capture_stdout { Rake::Task['variants:audit'].invoke }
    expect(output).to include("External IDs by source:")
    expect(output).to include("No orphan external ID mappings")
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
