class CartiController < ApplicationController
  def index
    @products = Product
      .joins(:categories)
      .where(categories: { name: ['carte', 'fizic'] })
      .group('products.id')
      .having('COUNT(DISTINCT categories.id) = 2')
  end
  def show
    @product = Product.find(params[:id])
  end
end
