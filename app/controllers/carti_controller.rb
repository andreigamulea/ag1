class CartiController < ApplicationController
  def index
    @products = Product
      .select(:id, :name, :price, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
      .joins(:categories)
      .where(categories: { name: ['carte', 'fizic'] })
      .group('products.id')
      .having('COUNT(DISTINCT categories.name) >= 2')

    # Filtrare adițională după categorie (opțional)
    if params[:category].present?
      @products = @products.joins(:categories).where(categories: { slug: params[:category] })
      @current_category = Category.find_by(slug: params[:category])
    end

    @products = @products.page(params[:page]).per(20)
  end

  def show
    @product = Product
      .select(:id, :name, :price, :description, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url, :external_image_urls, :meta_title, :meta_description, :slug)
      .find(params[:id])

    # Verifică dacă există produse în coș
    @cart_has_items = session[:cart].present? && session[:cart].any?

    # Produse similare (din aceleași categorii, exclus produsul curent)
    category_ids = @product.category_ids
    if category_ids.present?
      @similar_products = Product
        .select(:id, :name, :price, :external_image_url)
        .joins(:categories)
        .where(categories: { id: category_ids })
        .where.not(id: @product.id)
        .where(status: 'active')
        .distinct
        .limit(4)
    else
      @similar_products = []
    end
  end
end
