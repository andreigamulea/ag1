class ProductsController < ApplicationController
  before_action :set_product, only: [:show, :edit, :update, :destroy, :purge_attached_file]
  before_action :load_option_types, only: [:new, :edit, :create, :update]
  after_action :cleanup_memory, only: [:create, :update, :show, :edit, :new], if: :production?

  helper_method :preload_variants

  # Products show is a shop page (product details)
  # Products index, new, edit, update, destroy are admin pages
  def is_shop_page?
    action_name == 'show'
  end

  def is_admin_page?
    %w[index new edit update destroy purge_image force_gc].include?(action_name)
  end

  # GET /products or /products.json
  def index
    @products = Product.all
  end

  # GET /products/1 or /products/1.json
  def show
  end

  # GET /products/new
  def new
    @product = Product.new
  end

  # GET /products/1/edit
  def edit
  end

  # POST /products or /products.json
  def create
    @product = Product.new(product_params)

    respond_to do |format|
      if @product.save
        generate_variants_for(@product)

        format.html { redirect_to @product, notice: "Product was successfully created." }
        format.json { render :show, status: :created, location: @product }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @product.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      new_images = params[:product].delete(:secondary_images)
      new_files = params[:product].delete(:attached_files)

      product_params = product_params()
      product_params[:category_ids] = product_params[:category_ids]&.reject(&:blank?) || []

      if @product.update(product_params)
        @product.secondary_images.attach(new_images) if new_images.present?
        @product.attached_files.attach(new_files) if new_files.present?

        generate_variants_for(@product)

        format.html { redirect_to @product, notice: "Produs actualizat cu succes." }
        format.json { render :show, status: :ok, location: @product }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @product.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /products/1 or /products/1.json
  def destroy
    @product.archive!

    respond_to do |format|
      format.html { redirect_to products_path, status: :see_other, notice: "Produsul a fost arhivat." }
      format.json { head :no_content }
    end
  end

  def purge_image
    image = ActiveStorage::Attachment.find(params[:image_id])
    image.purge
    redirect_back fallback_location: edit_product_path(params[:id]), notice: "Imaginea a fost ștearsă."
  end

  def force_gc
    before_rss = MemoryLogger.fetch_memory_usage # în MB
    before_heap = GC.stat[:heap_live_slots]

    GC.start(full_mark: true, immediate_sweep: true)

    after_rss = MemoryLogger.fetch_memory_usage # în MB
    after_heap = GC.stat[:heap_live_slots]

    freed_mb = before_rss - after_rss
    freed_heap_diff = before_heap - after_heap

    # fallback dacă RSS nu s-a modificat semnificativ
    if freed_mb <= 0 && freed_heap_diff > 0
      estimated_mb = (freed_heap_diff * 40.0 / 1024).round(2)
      freed_mb = estimated_mb
      note = "Simulare GC manual (heap: #{before_heap} → #{after_heap})"
    else
      note = "GC manual (heap: #{before_heap} → #{after_heap})"
    end

    MemoryLog.create!(
      used_memory_mb: after_rss,
      reclaimed_mb: freed_mb,
      note: note
    )

    redirect_to ram_logs_path
  end

  def purge_external_file
    @product = Product.find(params[:id])
    url = CGI.unescape(params[:url])

    if @product.external_file_urls.present?
      @product.external_file_urls.delete(url)
      @product.save
      flash[:notice] = "Fișierul a fost șters."
    else
      flash[:alert] = "Fișierul nu a fost găsit."
    end

    redirect_to @product
  end

  def simulate_memory_usage_and_gc
    before_rss = MemoryLogger.fetch_memory_usage
    before_heap = GC.stat[:heap_available_slots]

    # Simulăm utilizare intensă de memorie
    garbage = []
    100_000.times do
      garbage << "X" * 1024 # 1KB per obiect => ~100MB
    end

    # Eliminăm referințele
    garbage = nil

    # Forțăm GC
    GC.start(full_mark: true, immediate_sweep: true)

    after_rss = MemoryLogger.fetch_memory_usage
    after_heap = GC.stat[:heap_available_slots]
    freed_mb = [(before_rss - after_rss), 0].max.round(2)

    note = "Simulare GC manual (heap: #{before_heap} → #{after_heap})"

    MemoryLog.create!(
      used_memory_mb: after_rss,
      reclaimed_mb: freed_mb,
      note: note
    )

    redirect_to ram_logs_path, notice: "Simulare GC efectuată – eliberat: #{freed_mb} MB"
  end

  def fetch_memory_usage
    require 'sys/proctable'
    info = Sys::ProcTable.ps.find { |p| p.pid == Process.pid }
    return 0 unless info

    if RbConfig::CONFIG['host_os'] =~ /linux/
      (info.rss.to_f / 1024 / 1024).round(2)
    elsif RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
      (info.working_set_size.to_f / 1024 / 1024).round(2)
    else
      0
    end
  end

  require 'net/http'
  require 'uri'

  def test_cdn_url(attachment, resize: [200, 200])
    helper = Class.new { include Rails.application.routes.url_helpers }.new
    variant = attachment.variant(resize_to_limit: resize).processed
    cdn_url = "https://ayus-cdn.b-cdn.net" +
              helper.rails_representation_path(variant, only_path: true)

    uri = URI.parse(cdn_url)
    response = Net::HTTP.get_response(uri)

    puts "CDN URL: #{cdn_url}"
    puts "Status: #{response.code} #{response.message}"
    puts "Content-Type: #{response['Content-Type']}"
  rescue => e
    puts "Eroare: #{e.message}"
  end

  def purge_main_image
    @product = Product.find(params[:id])
    @product.main_image.purge if @product.main_image.attached?
    redirect_back fallback_location: edit_product_path(@product), notice: "Imaginea principală a fost ștearsă."
  end

  def purge_attached_file
    file = @product.attached_files.find(params[:file_id])
    file.purge
    redirect_back fallback_location: edit_product_path(@product), notice: "Fișierul a fost șters."
  end

  def new_category
    @product = Product.find(params[:id])
    @category = Category.new
  end

  def create_category
    @product = Product.find(params[:id])
    @category = Category.new(category_params)
    if @category.save
      @product.categories << @category
      redirect_to edit_categories_product_path(@product), notice: "Categorie creată și asociată produsului."
    else
      render :new_category, status: :unprocessable_entity
    end
  end

  def edit_categories
    @product = Product.find(params[:id])
    @categories = Category.all
  end

  def update_categories
    @product = Product.find(params[:id])
    if @product.update(category_ids: params[:product][:category_ids])
      redirect_to @product, notice: "Categorii actualizate cu succes."
    else
      @categories = Category.all
      render :edit_categories, status: :unprocessable_entity
    end
  end

  def categories_index
    @categories = Category.order(:name)
  end

  def new_standalone_category
    @category = Category.new
  end

  def create_standalone_category
    @category = Category.new(category_params)
    if @category.save
      redirect_to categories_index_products_path, notice: "Categorie creată cu succes."
    else
      render :new_standalone_category, status: :unprocessable_entity
    end
  end

  def update_standalone_category
    @category = Category.find(params[:id])
    if @category.update(category_params)
      redirect_to categories_index_products_path, notice: "Categorie actualizată cu succes."
    else
      render :edit_standalone_category, status: :unprocessable_entity
    end
  end

  def show_standalone_category
    @category = Category.find_by(id: params[:id])
    if @category.nil?
      redirect_to categories_index_products_path, alert: "Categoria nu a fost găsită."
    end
  end
  def edit_standalone_category
    @category = Category.find(params[:id])
  end

  def delete_standalone_category
    @category = Category.find(params[:id])
    @category.destroy
    redirect_to categories_index_products_path, notice: "Categorie ștearsă cu succes."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_product
      @product = if params[:id] =~ /\A\d+\z/
        Product.find(params[:id])
      else
        Product.find_by!(slug: params[:id])
      end
    end

    # Only allow a list of trusted parameters through.
    def product_params
      clean_params = params.require(:product).permit(
        :name, :slug, :description_title, :description,
        :price, :cost_price, :discount_price,
        :sku, :stock, :track_inventory, :stock_status,
        :sold_individually, :available_on, :discontinue_on,
        :height, :width, :depth, :weight,
        :meta_title, :meta_description, :meta_keywords,
        :status, :featured, :requires_login,
        :product_type, :delivery_method, :visible_to_guests,
        :taxable, :coupon_applicable, :custom_attributes,
        :external_image_url, :vat,
        external_file_urls: [],
        external_image_urls: [],
        category_ids: [],
        variants_attributes: [:id, :sku, :price, :stock, :vat_rate, :status, :external_image_url, :_destroy, option_value_ids: [], external_image_urls: []]
      )

      # ✅ Parsează JSON-ul dacă este string
      if clean_params[:custom_attributes].is_a?(String)
        begin
          clean_params[:custom_attributes] = JSON.parse(clean_params[:custom_attributes])
        rescue JSON::ParserError
          clean_params[:custom_attributes] = {}
        end
      end

      # elimină duplicatele
      clean_params[:external_image_urls] = clean_params[:external_image_urls].uniq.compact if clean_params[:external_image_urls]

      clean_params
    end

    def category_params
      params.require(:category).permit(:name, :slug, :description, :meta_title, :meta_description)
    end

    def cleanup_memory
      before_rss = fetch_memory_usage
      before_heap = GC.stat[:heap_live_slots] rescue nil

      GC.start(full_mark: true, immediate_sweep: true)

      after_rss = fetch_memory_usage
      after_heap = GC.stat[:heap_live_slots] rescue nil

      freed = (before_rss - after_rss).round(2)
      MemoryLog.create!(
        used_memory_mb: after_rss,
        freed_memory_mb: freed,
        note: "GC automat (#{action_name}) – heap: #{before_heap} → #{after_heap}"
      )
    end

    def production?
      Rails.env.production?
    end

    def generate_variants_for(product)
      # Stub - variant generation se face prin nested attributes acum
    end

    def load_option_types
      @option_types = OptionType.includes(:option_values).order(:position).to_a
    end

    def preload_variants(product)
      return [] unless product.persisted?

      variants = product.variants.order(:id).to_a

      if variants.any?
        ActiveRecord::Associations::Preloader.new(
          records: variants,
          associations: [:option_values, :order_items]
        ).call

        if product.class.reflect_on_association(:variant_external_ids) ||
           Variant.reflect_on_association(:external_ids)
          ActiveRecord::Associations::Preloader.new(
            records: variants,
            associations: [:external_ids]
          ).call
        end
      end

      variants
    end
end