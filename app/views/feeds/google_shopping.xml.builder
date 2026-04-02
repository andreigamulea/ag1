base_url = (@feed.link.presence || request.base_url).chomp('/')

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.rss version: "2.0", "xmlns:g" => "http://base.google.com/ns/1.0" do
  xml.channel do
    xml.title @feed.title.presence || @feed.name
    xml.description @feed.description.presence || "Google Shopping Feed"
    xml.link base_url

    @products.each do |product|
      product_link = "#{base_url}/products/#{product.slug}"

      if @feed.include_variants && product.variants.active.any?
        product.variants.active.includes(:option_values).each do |variant|
          xml.item do
            xml.tag! "g:id", variant.sku
            xml.title "#{product.name} - #{variant.options_text}"
            xml.description strip_tags(product.description).to_s.truncate(5000)
            xml.link product_link
            xml.tag! "g:image_link", variant.external_image_url.presence || product.external_image_url
            xml.tag! "g:availability", variant.stock > 0 ? "in_stock" : "out_of_stock"
            xml.tag! "g:price", "#{variant.price} #{@feed.currency}"
            if variant.promo_active? && variant.discount_price.present?
              xml.tag! "g:sale_price", "#{variant.discount_price} #{@feed.currency}"
            end
            xml.tag! "g:brand", product.brand if product.brand.present?
            xml.tag! "g:gtin", variant.ean if variant.ean.present?
            xml.tag! "g:mpn", variant.sku
            xml.tag! "g:condition", "new"
            xml.tag! "g:item_group_id", product.sku
            if product.categories.any?
              xml.tag! "g:product_type", product.categories.map(&:name).join(" > ")
            end
            # Variant option values as custom labels
            variant.option_values.each_with_index do |ov, idx|
              xml.tag! "g:custom_label_#{idx}", ov.display_name if idx < 5
            end
            if variant.weight.present?
              xml.tag! "g:shipping_weight", "#{variant.weight} g"
            end
          end
        end
      else
        xml.item do
          xml.tag! "g:id", product.sku
          xml.title product.name
          xml.description strip_tags(product.description).to_s.truncate(5000)
          xml.link product_link
          xml.tag! "g:image_link", product.external_image_url if product.external_image_url.present?
          if product.external_image_urls.present?
            product.external_image_urls.first(10).each do |url|
              xml.tag! "g:additional_image_link", url
            end
          end
          xml.tag! "g:availability", product.in_stock? ? "in_stock" : "out_of_stock"
          xml.tag! "g:price", "#{product.price} #{@feed.currency}"
          if product.promo_active? && product.discount_price.present?
            xml.tag! "g:sale_price", "#{product.discount_price} #{@feed.currency}"
          end
          xml.tag! "g:brand", product.brand if product.brand.present?
          xml.tag! "g:mpn", product.sku
          xml.tag! "g:condition", "new"
          if product.categories.any?
            xml.tag! "g:product_type", product.categories.map(&:name).join(" > ")
          end
          if product.weight.present?
            xml.tag! "g:shipping_weight", "#{product.weight} g"
          end
        end
      end
    end
  end
end
