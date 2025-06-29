class ProductsController < ApplicationController
  before_action :set_product, only: %i[ show edit update destroy ]
  before_action :set_product, only: [:show, :edit, :update, :destroy, :purge_attached_file]


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
  puts "=== PARAMS[:product] ==="
  puts params[:product].inspect

  @product = Product.new(product_params)

  puts "=== product_params ==="
  puts product_params.inspect

  puts "=== Category IDs in product ==="
  puts @product.category_ids.inspect

  respond_to do |format|
    if @product.save
      puts "=== Product saved successfully ==="
      puts @product.categories.map(&:name).inspect

      format.html { redirect_to @product, notice: "Product was successfully created." }
      format.json { render :show, status: :created, location: @product }
    else
      puts "=== Product save failed ==="
      puts @product.errors.full_messages.inspect

      format.html { render :new, status: :unprocessable_entity }
      format.json { render json: @product.errors, status: :unprocessable_entity }
    end
  end
end


 # PATCH/PUT /products/1 or /products/1.json
def update
  respond_to do |format|
    # 1. extragem secondary_images și attached_files din params
    new_images = params[:product].delete(:secondary_images)
    new_files = params[:product].delete(:attached_files)

    # 2. actualizăm restul atributelor
    if @product.update(product_params)
      # 3. atașăm fișierele noi, dacă există
      @product.secondary_images.attach(new_images) if new_images.present?
      @product.attached_files.attach(new_files) if new_files.present?

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
    :name, :slug, :description_title, :description,
    :price, :cost_price, :discount_price,
    :sku, :stock, :track_inventory, :stock_status, :sold_individually,
    :available_on, :discontinue_on,
    :height, :width, :depth, :weight,
    :meta_title, :meta_description, :meta_keywords,
    :status, :featured,
    :custom_attributes,
    :main_image,
    :requires_login,
    :product_type,
    :delivery_method,
    :visible_to_guests,
    :taxable,
    :coupon_applicable,
    category_ids: [],
    attached_files: [],
    secondary_images: []
  )
end


def category_params
  params.require(:category).permit(:name, :slug)
end

end
