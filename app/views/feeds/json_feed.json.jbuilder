base_url = (@feed.link.presence || request.base_url).chomp('/')

json.version "https://jsonfeed.org/version/1.1"
json.title @feed.title.presence || @feed.name
json.description @feed.description.presence || "Produse din #{@feed.name}"
json.home_page_url base_url
json.feed_url "#{base_url}/feeds/#{@feed.slug}.json"
json.language @feed.language

items = []

@products.each do |product|
  if @feed.include_variants && product.variants.active.any?
    product.variants.active.each do |variant|
      items << {
        id: variant.sku,
        title: "#{product.name} - #{variant.options_text}",
        url: "#{base_url}/products/#{product.slug}",
        content_text: strip_tags(product.description).to_s.truncate(500),
        date_published: product.created_at.iso8601,
        date_modified: product.updated_at.iso8601,
        image: variant.external_image_url.presence || product.external_image_url,
        tags: product.categories.map(&:name),
        _ag1: {
          sku: variant.sku,
          price: variant.price.to_f,
          sale_price: variant.promo_active? && variant.discount_price.present? ? variant.discount_price.to_f : nil,
          currency: @feed.currency,
          stock: variant.stock,
          availability: variant.stock > 0 ? "in_stock" : "out_of_stock",
          brand: product.brand,
          ean: variant.ean,
          options: variant.options_text,
          categories: product.categories.map(&:name)
        }
      }
    end
  else
    items << {
      id: product.sku,
      title: product.name,
      url: "#{base_url}/products/#{product.slug}",
      content_text: strip_tags(product.description).to_s.truncate(500),
      date_published: product.created_at.iso8601,
      date_modified: product.updated_at.iso8601,
      image: product.external_image_url,
      tags: product.categories.map(&:name),
      _ag1: {
        sku: product.sku,
        price: product.price.to_f,
        sale_price: product.promo_active? && product.discount_price.present? ? product.discount_price.to_f : nil,
        currency: @feed.currency,
        stock: product.stock,
        availability: product.in_stock? ? "in_stock" : "out_of_stock",
        brand: product.brand,
        categories: product.categories.map(&:name)
      }
    }
  end
end

json.items items
