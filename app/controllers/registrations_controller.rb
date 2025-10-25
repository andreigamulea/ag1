# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  before_action :authenticate_user!, only: [:deactivate]

  # Metodă nouă pentru dezactivare cont
  def deactivate
    if current_user.valid_password?(params[:user][:current_password])
      current_user.deactivate!
      sign_out current_user
      redirect_to root_path, notice: "Contul tău a fost dezactivat cu succes. Poți să-l reactivezi oricând contactându-ne la ayushcellromania@gmail.com."
    else
      redirect_to edit_user_registration_path, alert: "Parola curentă este incorectă."
    end
  end
end