class CartiController < ApplicationController
  def index
    @products = Product
      .select(:id, :name, :price, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
      .joins(:categories)
      .where(categories: { name: ['carte', 'fizic'] })
      .group('products.id')
      .having('COUNT(DISTINCT categories.name) >= 2')
      .page(params[:page]).per(20)
  end

  def show
    @product = Product
      .select(:id, :name, :price, :description, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url, :external_image_urls)
      .find(params[:id])
  end
end
