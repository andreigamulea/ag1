class CouponsController < ApplicationController
  before_action :set_coupon, only: [:edit, :update, :destroy]

  def index
    @coupons = Coupon.order(created_at: :desc)
  end

  def new
    @coupon = Coupon.new
  end

  def create
    @coupon = Coupon.new(coupon_params)
    if @coupon.save
      redirect_to coupons_path, notice: "Cuponul a fost creat cu succes."
    else
      flash.now[:alert] = "Eroare la salvarea cuponului."
      render :new
    end
  end

  def edit
  end

  def update
    if @coupon.update(coupon_params)
      redirect_to coupons_path, notice: "Cuponul a fost actualizat."
    else
      flash.now[:alert] = "Eroare la actualizare."
      render :edit
    end
  end

  def destroy
    @coupon.destroy
    redirect_to coupons_path, notice: "Cuponul a fost șters."
  end

  private

  def set_coupon
    @coupon = Coupon.find(params[:id])
  end

  def coupon_params
    params.require(:coupon).permit(
      :code, :discount_type, :discount_value, :active,
      :starts_at, :expires_at, :usage_limit, :usage_count,
      :minimum_cart_value, :minimum_quantity, :product_id,
      :free_shipping
    )
  end
end
