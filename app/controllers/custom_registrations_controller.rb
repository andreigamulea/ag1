class CustomRegistrationsController < Devise::RegistrationsController
  before_action :authenticate_user!, only: [:deactivate]

  # Devise registration/edit pages use shop layout
  def is_shop_page?
    true
  end

  def deactivate
    # Verifică dacă parola a fost trimisă
    if params[:user].present? && params[:user][:current_password].present?
      if current_user.valid_password?(params[:user][:current_password])
        current_user.deactivate!
        sign_out current_user
        redirect_to root_path, notice: "Contul tău a fost dezactivat cu succes. Poți să-l reactivezi oricând contactându-ne la ayushcellromania@gmail.com."
      else
        redirect_to edit_user_registration_path, alert: "Parola curentă este incorectă."
      end
    else
      redirect_to edit_user_registration_path, alert: "Te rugăm să introduci parola curentă."
    end
  end
end