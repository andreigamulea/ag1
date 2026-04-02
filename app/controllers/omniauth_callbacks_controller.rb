class OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :google_oauth2

  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      session["devise.google_data"] = {
        "provider" => request.env["omniauth.auth"]["provider"],
        "uid" => request.env["omniauth.auth"]["uid"],
        "info" => {
          "email" => request.env["omniauth.auth"].dig("info", "email"),
          "name" => request.env["omniauth.auth"].dig("info", "name")
        }
      }
      redirect_to new_user_registration_url
    end
  end

  def failure
    redirect_to new_user_session_path
  end
end
