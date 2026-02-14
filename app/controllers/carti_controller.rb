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
      .select(:id, :name, :slug, :price, :discount_price, :promo_active, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url)
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

    # Preload active variants grouped by product_id (for expanding variant products)
    product_ids = @products.map(&:id)
    if product_ids.any?
      @product_variants = Variant.where(product_id: product_ids, status: :active)
        .includes(:option_values)
        .order(:product_id, :id)
        .group_by(&:product_id)
    else
      @product_variants = {}
    end
  end

  def show
    @product = if params[:slug] =~ /\A\d+\z/
      Product
        .select(:id, :name, :price, :discount_price, :promo_active, :description, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url, :external_image_urls, :meta_title, :meta_description, :slug)
        .find(params[:slug])
    else
      Product
        .select(:id, :name, :price, :discount_price, :promo_active, :description, :stock, :stock_status, :custom_attributes, :track_inventory, :external_image_url, :external_image_urls, :meta_title, :meta_description, :slug)
        .find_by!(slug: params[:slug])
    end

    # Preload variante active cu optiunile lor
    @active_variants = @product.variants.active.includes(:option_values).order(:id).to_a

    if @active_variants.any?
      # Load product_option_types din tabel (cu primary flag)
      pot_records = @product.product_option_types.includes(option_type: :option_values).to_a

      if pot_records.empty?
        # Backward compatibility: derivăm din variante dacă nu există records
        ot_ids = @active_variants.flat_map { |v| v.option_values.map(&:option_type_id) }.uniq
        @product_option_types = OptionType.includes(:option_values).where(id: ot_ids).order(:position).to_a
        @primary_option_type = @product_option_types.first
        @secondary_option_types = @product_option_types.drop(1)
      else
        all_ots = pot_records.map(&:option_type)
        primary_pot = pot_records.find(&:primary?)
        @primary_option_type = primary_pot&.option_type || all_ots.first
        @secondary_option_types = all_ots.reject { |ot| ot.id == @primary_option_type&.id }
        @product_option_types = all_ots
      end
    else
      @product_option_types = []
      @primary_option_type = nil
      @secondary_option_types = []
    end

    # Verifică dacă există produse în coș
    @cart_has_items = session[:cart].present? && session[:cart].any?

    # Produse similare (din aceleași categorii, exclus produsul curent)
    category_ids = @product.category_ids
    if category_ids.present?
      @similar_products = Product
        .select(:id, :name, :slug, :price, :discount_price, :promo_active, :external_image_url)
        .joins(:categories)
        .where(categories: { id: category_ids })
        .where.not(id: @product.id)
        .where(status: 'active')
        .distinct
        .limit(5)

      # Preload variant prices for similar products
      similar_ids = @similar_products.map(&:id)
      if similar_ids.any?
        @similar_variant_prices = Variant.where(product_id: similar_ids, status: :active)
          .group(:product_id)
          .pluck(:product_id,
            Arel.sql("MIN(CASE WHEN promo_active = true AND discount_price IS NOT NULL AND discount_price > 0 THEN discount_price ELSE price END)"))
          .each_with_object({}) { |(pid, min_p), h| h[pid] = min_p }
      else
        @similar_variant_prices = {}
      end
    else
      @similar_products = []
      @similar_variant_prices = {}
    end
  end
end
