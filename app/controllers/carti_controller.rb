class CartiController < ApplicationController
  def index
    # Produse care au ambele categorii 'carte' și 'fizic'
    base_product_ids = Product
      .joins(:categories)
      .where(categories: { name: ['carte', 'fizic'] })
      .group('products.id')
      .having('COUNT(DISTINCT categories.name) >= 2')
      .pluck(:id)

    @products = Product
      .select(:id, :name, :price, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
      .where(id: base_product_ids)

    # Filtrare adițională după categorie (opțional)
    if params[:category].present?
      @current_category = Category.find_by(slug: params[:category])
      if @current_category
        filtered_ids = Product
          .joins(:categories)
          .where(id: base_product_ids)
          .where(categories: { id: @current_category.id })
          .pluck(:id)
        @products = @products.where(id: filtered_ids)
      end
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
