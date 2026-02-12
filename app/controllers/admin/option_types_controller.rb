class Admin::OptionTypesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_option_type, only: [:edit, :update, :destroy]

  def index
    @option_types = OptionType.includes(:option_values, :products).order(:position)
  end

  def new
    @option_type = OptionType.new
  end

  def create
    @option_type = OptionType.new(option_type_params)

    if @option_type.save
      redirect_to edit_admin_option_type_path(@option_type),
                  notice: "Option Type '#{@option_type.name}' created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @option_type = OptionType.includes(:option_values).find(params[:id])
    @new_option_value = @option_type.option_values.build
  end

  def update
    if @option_type.update(option_type_params)
      redirect_to edit_admin_option_type_path(@option_type),
                  notice: "Option Type updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    products_count = @option_type.products.count

    if products_count > 0
      redirect_to admin_option_types_path,
                  alert: "Cannot delete '#{@option_type.name}'. It's used by #{products_count} products."
    else
      @option_type.destroy
      redirect_to admin_option_types_path,
                  notice: "Option Type '#{@option_type.name}' deleted successfully."
    end
  end

  private

  def set_option_type
    @option_type = OptionType.find(params[:id])
  end

  def option_type_params
    params.require(:option_type).permit(:name, :presentation, :position)
  end

  def require_admin
    redirect_to root_path, alert: "Access denied." unless current_user&.admin?
  end
end
