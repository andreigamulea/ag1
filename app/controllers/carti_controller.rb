class CartiController < ApplicationController
  # Books/Carti is a shop page
  def is_shop_page?
    true
  end

  def index
    # Produse care au ambele categorii 'carte' și 'fizic'
    base_product_ids = Product
      .joins(:categories)
      .where(categories: { name: ['carte', 'fizic'] })
      .group('products.id')
      .having('COUNT(DISTINCT categories.name) >= 2')
      .pluck(:id)

    @products = Product
      .select(:id, :name, :slug, :price, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
      .where(id: base_product_ids, status: 'active')

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
    @product = if params[:slug] =~ /\A\d+\z/
      Product
        .select(:id, :name, :price, :description, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url, :external_image_urls, :meta_title, :meta_description, :slug)
        .find(params[:slug])
    else
      Product
        .select(:id, :name, :price, :description, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url, :external_image_urls, :meta_title, :meta_description, :slug)
        .find_by!(slug: params[:slug])
    end

    # Preload variante active cu optiunile lor
    @active_variants = @product.variants.active.includes(:option_values).order(:id).to_a
    @product_option_types = if @active_variants.any?
      ot_ids = @active_variants.flat_map { |v| v.option_values.map(&:option_type_id) }.uniq
      OptionType.includes(:option_values).where(id: ot_ids).order(:position).to_a
    else
      []
    end

    # Verifică dacă există produse în coș
    @cart_has_items = session[:cart].present? && session[:cart].any?

    # Produse similare (din aceleași categorii, exclus produsul curent)
    category_ids = @product.category_ids
    if category_ids.present?
      @similar_products = Product
        .select(:id, :name, :slug, :price, :external_image_url)
        .joins(:categories)
        .where(categories: { id: category_ids })
        .where.not(id: @product.id)
        .where(status: 'active')
        .distinct
        .limit(5)
    else
      @similar_products = []
    end
  end
end
