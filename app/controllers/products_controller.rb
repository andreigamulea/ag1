class ProductsController < ApplicationController
  before_action :set_product, only: %i[ show edit update destroy ]

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
        format.html { redirect_to @product, notice: "Product was successfully created." }
        format.json { render :show, status: :created, location: @product }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @product.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /products/1 or /products/1.json
def update
  respond_to do |format|
    # 1. extragem secondary_images din params
    new_images = params[:product].delete(:secondary_images)

    # 2. actualizăm restul atributele fără secondary_images
    if @product.update(product_params)
      # 3. atașăm doar acum noile imagini (peste cele existente)
      @product.secondary_images.attach(new_images) if new_images.present?

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
    secondary_images: []
  )
end



end
