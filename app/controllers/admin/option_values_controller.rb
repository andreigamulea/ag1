class Admin::OptionValuesController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_option_type

  def create
    @option_value = @option_type.option_values.build(option_value_params)

    # Auto-assign next position
    @option_value.position = (@option_type.option_values.maximum(:position) || -1) + 1

    if @option_value.save
      redirect_to edit_admin_option_type_path(@option_type),
                  notice: "Option Value '#{@option_value.name}' added."
    else
      @new_option_value = @option_value
      render 'admin/option_types/edit', status: :unprocessable_entity
    end
  end

  def update
    @option_value = @option_type.option_values.find(params[:id])

    if @option_value.update(option_value_params)
      redirect_to edit_admin_option_type_path(@option_type),
                  notice: "Option Value updated."
    else
      render 'admin/option_types/edit', status: :unprocessable_entity
    end
  end

  def destroy
    @option_value = @option_type.option_values.find(params[:id])

    # Check if used in variants
    variants_count = @option_value.variants.count

    if variants_count > 0
      redirect_to edit_admin_option_type_path(@option_type),
                  alert: "Cannot delete '#{@option_value.name}'. It's used by #{variants_count} variants."
    else
      @option_value.destroy
      redirect_to edit_admin_option_type_path(@option_type),
                  notice: "Option Value '#{@option_value.name}' deleted."
    end
  end

  private

  def set_option_type
    @option_type = OptionType.find(params[:option_type_id])
  end

  def option_value_params
    params.require(:option_value).permit(:name, :presentation, :position)
  end

  def require_admin
    redirect_to root_path, alert: "Access denied." unless current_user&.admin?
  end
end
