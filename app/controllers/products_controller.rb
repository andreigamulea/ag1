class ProductsController < ApplicationController
  before_action :set_product, only: %i[ show edit update destroy ]
  before_action :set_product, only: [:show, :edit, :update, :destroy, :purge_attached_file]
  after_action :cleanup_memory, only: [:create, :update, :show, :edit, :new]


  # GET /products or /products.json
  def index
    @products = Product.all
  end

  # GET /products/1 or /products/1.json
  def show
  end

  # #GET /products/new
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
    @product.destroy!

    respond_to do |format|
      format.html { redirect_to products_path, status: :see_other, notice: "Product was successfully destroyed." }
      format.json { head :no_content }
    end
  end

def purge_image
  image = ActiveStorage::Attachment.find(params[:image_id])
  image.purge
  redirect_back fallback_location: edit_product_path(params[:id]), notice: "Imaginea a fost ștearsă."
end

def force_gc
  before_rss = fetch_memory_usage
  before_heap = GC.stat[:heap_used]

  GC.start(full_mark: true, immediate_sweep: true)

  after_rss = fetch_memory_usage
  after_heap = GC.stat[:heap_used]

  freed = (before_rss - after_rss).round(2)

  Rails.logger.info "[GC] GC declanșat manual – RSS: #{before_rss} → #{after_rss} MB | Heap: #{before_heap} → #{after_heap}"

  MemoryLog.create!(
    used_memory_mb: after_rss,
    freed_memory_mb: freed,
    note: "GC manual (heap: #{before_heap} → #{after_heap})"
  )

  redirect_to admin_path, notice: "🧹 GC declanșat manual – Memorie eliberată: #{freed} MB"
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
      @product = Product.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
def product_params
  params.require(:product).permit(
    :name, :slug, :description_title, :description, :price, :cost_price,
    :discount_price, :sku, :stock, :track_inventory, :stock_status,
    :sold_individually, :available_on, :discontinue_on, :height, :width,
    :depth, :weight, :meta_title, :meta_description, :meta_keywords, :status,
    :featured, :requires_login, :product_type, :delivery_method,
    :visible_to_guests, :taxable, :coupon_applicable, :custom_attributes,
    :main_image, attached_files: [], secondary_images: [], category_ids: []
  )
end


def category_params
  params.require(:category).permit(:name, :slug)
end

def cleanup_memory
  GC.start(full_mark: true, immediate_sweep: true)
  Rails.logger.info "[GC] ✅ GC finalizat după #{action_name}"

  if request.format.html? && response.body.present?
    flash.now[:notice] = "🧹 Memorie curățată manual după #{action_name} (#{Time.now.strftime('%H:%M:%S')})"
  end
end



def generate_variants_for(product)
  if product.main_image.attached? && product.main_image.variable?
    GenerateImageVariantsJob.perform_now(product.main_image, [300, 300])
  end

  product.secondary_images.each do |img|
    GenerateImageVariantsJob.perform_now(img, [150, 150]) if img.variable?
  end
  GC.start(full_mark: true, immediate_sweep: true)
end









end
