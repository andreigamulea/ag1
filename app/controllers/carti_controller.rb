class CartiController < ApplicationController
  def index
    @products = Product.select(:id, :name, :price, :stock, :stock_status, :custom_attributes, :track_inventory)
                      .joins(:categories)
                      .where(categories: { name: ['carte', 'fizic'] })
                      .group('products.id')
                      .having('COUNT(DISTINCT categories.name) >= 2')
                      .includes(:main_image_attachment, :secondary_images_attachments)
                      .page(params[:page]).per(20)
  end

  def show
    @product = Product.select(:id, :name, :price, :description, :stock, :stock_status, :custom_attributes, :track_inventory)
                     .includes(:main_image_attachment, :secondary_images_attachments)
                     .find(params[:id])
    Rails.logger.debug "Main image attached: #{@product.main_image.attached?}"
    Rails.logger.debug "Secondary images count: #{@product.secondary_images.count}"
  end
end