class CustomRegistrationsController < Devise::RegistrationsController
  before_action :authenticate_user!, only: [:deactivate]

  # Devise registration/edit pages use shop layout
  def is_shop_page?
    true
  end

  # Redirect /users/edit to new dashboard
  def edit
    redirect_to contul_meu_path(section: "settings")
  end

  # Override update to render dashboard on error
  def update
    self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
    prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)
    resource_updated = update_resource(resource, account_update_params)

    if resource_updated
      set_flash_message_for_update(resource, prev_unconfirmed_email)
      bypass_sign_in resource, scope: resource_name if sign_in_after_change_password?
      redirect_to contul_meu_path(section: "settings")
    else
      clean_up_passwords resource
      set_minimum_password_length
      @section = "settings"
      @resource = resource
      @addresses = []
      @orders = []
      render "account/show", status: :unprocessable_entity
    end
  end

  def deactivate
    if params[:user].present? && params[:user][:current_password].present?
      if current_user.valid_password?(params[:user][:current_password])
        current_user.deactivate!
        sign_out current_user
        redirect_to root_path, notice: "Contul tau a fost dezactivat cu succes. Poti sa-l reactivezi oricand contactandu-ne la ayushcellromania@gmail.com."
      else
        redirect_to contul_meu_path(section: "settings"), alert: "Parola curenta este incorecta."
      end
    else
      redirect_to contul_meu_path(section: "settings"), alert: "Te rugam sa introduci parola curenta."
    end
  end

  protected

  def after_update_path_for(resource)
    contul_meu_path(section: "settings")
  end
end
