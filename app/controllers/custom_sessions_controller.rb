class CustomSessionsController < Devise::SessionsController
  def is_shop_page?
    true
  end

  protected

  def auth_options
    { scope: resource_name, recall: "#{controller_path}#new" }
  end

  def after_failed_login
    flash[:alert] = I18n.t("devise.failure.not_found_in_database")
  end
end
