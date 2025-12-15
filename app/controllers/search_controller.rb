class SearchController < ApplicationController
  def index
    @query = params[:q]&.strip
    
    if @query.blank?
      @products = []
      @total_results = 0
      return
    end
    
    # Căutare în produse
    @products = Product
      .select(:id, :name, :price, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
      .where("name ILIKE ? OR description ILIKE ?", "%#{@query}%", "%#{@query}%")
      .page(params[:page]).per(20)
    
    @total_results = @products.total_count
  end
end