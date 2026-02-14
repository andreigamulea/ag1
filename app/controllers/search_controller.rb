class SearchController < ApplicationController
  # Search is a shop page
  def is_shop_page?
    true
  end

  def index
    @query = params[:q]&.strip
    
    if @query.blank?
      @products = []
      @total_results = 0
      return
    end
    
    # Căutare în produse - DOAR ACTIVE
    @products = Product
      .select(:id, :name, :price, :discount_price, :promo_active, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
      .where(status: 'active')
      .where("name ILIKE ? OR description ILIKE ?", "%#{@query}%", "%#{@query}%")
      .page(params[:page]).per(20)
    
    @total_results = @products.total_count
  end
end