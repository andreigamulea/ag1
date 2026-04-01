class AccountController < ApplicationController
  before_action :authenticate_user!

  def is_shop_page?
    true
  end

  SECTIONS = %w[addresses billing settings orders].freeze

  # GET /contul-meu
  def show
    @section = SECTIONS.include?(params[:section]) ? params[:section] : "addresses"

    case @section
    when "addresses"
      @addresses = current_user.shipping_addresses
    when "billing"
      @addresses = current_user.billing_addresses
    when "settings"
      @resource = current_user
      @minimum_password_length = Devise.password_length.min
    when "orders"
      scope = current_user.orders.includes(:invoice, order_items: :product)

      # Filtru status
      if params[:status].present?
        scope = scope.where(status: params[:status])
      end

      # Filtru perioadă
      case params[:period]
      when "3m"
        scope = scope.where("placed_at >= ? OR created_at >= ?", 3.months.ago, 3.months.ago)
      when "6m"
        scope = scope.where("placed_at >= ? OR created_at >= ?", 6.months.ago, 6.months.ago)
      when /\A\d{4}\z/
        year = params[:period].to_i
        scope = scope.where("EXTRACT(YEAR FROM COALESCE(placed_at, created_at)) = ?", year)
      end

      # Cautare dupa nr. comanda sau nume produs
      if params[:q].present?
        query = params[:q].strip
        if query.match?(/\A\d+\z/)
          scope = scope.where(id: query.to_i)
        else
          scope = scope.joins(:order_items)
                       .where("order_items.product_name ILIKE ?", "%#{query}%")
                       .distinct
        end
      end

      per_page = [params[:per].to_i, 10].max
      per_page = 20 if per_page > 20
      @orders = scope.order(created_at: :desc).page(params[:page]).per(per_page)
    end
  end

  # GET /contul-meu/comenzi/:id
  def order_detail
    @order = current_user.orders
                         .includes(:invoice, order_items: :product)
                         .find(params[:id])
    @section = "orders"
  end

  private

  def resource
    @resource ||= current_user
  end
  helper_method :resource

  def resource_name
    :user
  end
  helper_method :resource_name

  def devise_mapping
    Devise.mappings[:user]
  end
  helper_method :devise_mapping
end
