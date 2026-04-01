class AddressesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_address, only: [:edit, :update, :destroy]

  def is_shop_page?
    true
  end

  def new
    type = %w[shipping billing].include?(params[:type]) ? params[:type] : "shipping"
    @address = current_user.addresses.build(address_type: type)
  end

  def create
    @address = current_user.addresses.build(address_params)
    if @address.save
      redirect_to contul_meu_path(section: @address.address_type == "billing" ? "billing" : "addresses"),
                  notice: "Adresa a fost salvata."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @address.update(address_params)
      redirect_to contul_meu_path(section: @address.address_type == "billing" ? "billing" : "addresses"),
                  notice: "Adresa a fost actualizata."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    type = @address.address_type
    @address.destroy
    redirect_to contul_meu_path(section: type == "billing" ? "billing" : "addresses"),
                notice: "Adresa a fost stearsa."
  end

  private

  def set_address
    @address = current_user.addresses.find(params[:id])
  end

  def address_params
    params.require(:address).permit(
      :address_type, :first_name, :last_name, :company_name, :cui,
      :phone, :email, :country, :county, :city, :postal_code,
      :street, :street_number, :block_details, :label, :default
    )
  end
end
