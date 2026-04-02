class Admin::FeedsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin
  before_action :set_feed, only: [:edit, :update, :destroy, :toggle_status, :preview]

  def is_admin_page?
    true
  end

  def index
    @feeds = Feed.order(created_at: :desc)
  end

  def new
    @feed = Feed.new(feed_type: 'rss', language: 'ro', currency: 'RON', link: 'https://ayus.ro')
    @categories = Category.ordered_tree
  end

  def create
    @feed = Feed.new(feed_params)
    @feed.selected_category_ids = params[:feed][:selected_category_ids] if params[:feed][:selected_category_ids]

    if @feed.save
      redirect_to admin_feeds_path, notice: "Feed-ul '#{@feed.name}' a fost creat cu succes."
    else
      @categories = Category.ordered_tree
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = Category.ordered_tree
  end

  def update
    @feed.selected_category_ids = params[:feed][:selected_category_ids] if params[:feed][:selected_category_ids]

    if @feed.update(feed_params)
      redirect_to admin_feeds_path, notice: "Feed-ul '#{@feed.name}' a fost actualizat."
    else
      @categories = Category.ordered_tree
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @feed.name
    @feed.destroy
    redirect_to admin_feeds_path, notice: "Feed-ul '#{name}' a fost sters."
  end

  def toggle_status
    @feed.update(status: @feed.active? ? :inactive : :active)
    redirect_to admin_feeds_path, notice: "Status-ul feed-ului '#{@feed.name}' a fost schimbat."
  end

  def preview
    @products = @feed.products.includes(:categories, :variants).limit(5)
  end

  private

  def set_feed
    @feed = Feed.find(params[:id])
  end

  def feed_params
    params.require(:feed).permit(
      :name, :slug, :feed_type, :title, :description, :link,
      :language, :currency, :include_variants, :include_out_of_stock,
      :products_limit, :status
    )
  end
end
