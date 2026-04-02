class FeedsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def show
    @feed = Feed.active.find_by!(slug: params[:slug])
    @products = @feed.products.includes(:categories, :variants => :option_values)
    @feed.touch_generated!

    respond_to do |format|
      format.xml do
        case @feed.feed_type
        when 'google_shopping'
          render 'feeds/google_shopping', formats: [:xml], layout: false
        else
          render 'feeds/rss', formats: [:xml], layout: false
        end
      end
      format.json { render 'feeds/json_feed', formats: [:json], layout: false }
      format.csv do
        csv_data = "\xEF\xBB\xBF" + generate_csv(@feed, @products)
        send_data csv_data, filename: "#{@feed.slug}.csv", type: 'text/csv; charset=utf-8'
      end
    end
  end

  private

  def generate_csv(feed, products)
    require 'csv'
    CSV.generate(headers: true, col_sep: feed.feed_type == 'facebook' ? "\t" : ',') do |csv|
      if feed.feed_type == 'facebook'
        csv << ['id', 'title', 'description', 'availability', 'condition', 'price', 'link',
                'image_link', 'additional_image_link', 'brand', 'google_product_category', 'sale_price']
        products.each do |product|
          if feed.include_variants && product.variants.active.any?
            product.variants.active.each do |variant|
              csv << facebook_variant_row(product, variant, feed)
            end
          else
            csv << facebook_product_row(product, feed)
          end
        end
      else
        csv << ['SKU', 'Nume', 'Descriere', 'Pret', 'Pret promotional', 'Stoc', 'Status',
                'Categorie', 'Brand', 'Imagine', 'Imagini aditionale', 'URL', 'EAN', 'Greutate']
        products.each do |product|
          if feed.include_variants && product.variants.active.any?
            product.variants.active.each do |variant|
              csv << csv_variant_row(product, variant, feed)
            end
          else
            csv << csv_product_row(product, feed)
          end
        end
      end
    end
  end

  def product_url_for(product, feed)
    base = (feed.link.presence || request.base_url).chomp('/')
    "#{base}/products/#{product.slug}"
  end

  def facebook_product_row(product, feed)
    [
      product.sku,
      product.name,
      ActionController::Base.helpers.strip_tags(product.description).to_s.truncate(5000),
      product.in_stock? ? 'in stock' : 'out of stock',
      'new',
      "#{product.price} #{feed.currency}",
      product_url_for(product, feed),
      product.external_image_url,
      product.external_image_urls&.join(' | '),
      product.brand,
      product.categories.first&.name,
      product.promo_active? && product.discount_price.present? ? "#{product.discount_price} #{feed.currency}" : nil
    ]
  end

  def facebook_variant_row(product, variant, feed)
    additional = variant.external_image_urls.presence || product.external_image_urls
    [
      variant.sku,
      "#{product.name} - #{variant.options_text}",
      ActionController::Base.helpers.strip_tags(product.description).to_s.truncate(5000),
      variant.stock > 0 ? 'in stock' : 'out of stock',
      'new',
      "#{variant.price} #{feed.currency}",
      product_url_for(product, feed),
      variant.external_image_url.presence || product.external_image_url,
      additional&.join(' | '),
      product.brand,
      product.categories.first&.name,
      variant.promo_active? && variant.discount_price.present? ? "#{variant.discount_price} #{feed.currency}" : nil
    ]
  end

  def csv_product_row(product, feed)
    [
      product.sku,
      product.name,
      ActionController::Base.helpers.strip_tags(product.description).to_s.truncate(500),
      product.price,
      product.promo_active? ? product.discount_price : nil,
      product.stock,
      product.status,
      product.categories.map(&:name).join(', '),
      product.brand,
      product.external_image_url,
      product.external_image_urls&.join(' | '),
      product_url_for(product, feed),
      nil,
      product.weight
    ]
  end

  def csv_variant_row(product, variant, feed)
    additional = variant.external_image_urls.presence || product.external_image_urls
    [
      variant.sku,
      "#{product.name} - #{variant.options_text}",
      ActionController::Base.helpers.strip_tags(product.description).to_s.truncate(500),
      variant.price,
      variant.promo_active? ? variant.discount_price : nil,
      variant.stock,
      variant.status,
      product.categories.map(&:name).join(', '),
      product.brand,
      variant.external_image_url.presence || product.external_image_url,
      additional&.join(' | '),
      product_url_for(product, feed),
      variant.ean,
      variant.weight
    ]
  end
end
