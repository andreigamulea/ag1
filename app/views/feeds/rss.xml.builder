base_url = (@feed.link.presence || request.base_url).chomp('/')

xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.rss version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom", "xmlns:dc" => "http://purl.org/dc/elements/1.1/", "xmlns:media" => "http://search.yahoo.com/mrss/" do
  xml.channel do
    xml.title @feed.title.presence || @feed.name
    xml.description @feed.description.presence || "Produse din #{@feed.name}"
    xml.link base_url
    xml.language @feed.language
    xml.lastBuildDate Time.current.rfc2822
    xml.generator "AG1 Feed Generator"
    xml.tag! "atom:link", href: "#{base_url}/feeds/#{@feed.slug}.xml", rel: "self", type: "application/rss+xml"

    @products.each do |product|
      product_link = "#{base_url}/products/#{product.slug}"

      if @feed.include_variants && product.variants.active.any?
        product.variants.active.includes(:option_values).each do |variant|
          xml.item do
            xml.title "#{product.name} - #{variant.options_text}"
            xml.description strip_tags(product.description).to_s.truncate(500)
            xml.link product_link
            xml.guid "#{base_url}/products/#{product.slug}?variant=#{variant.id}", isPermaLink: "false"
            xml.pubDate product.created_at.rfc2822
            xml.tag! "dc:creator", product.brand if product.brand.present?
            product.categories.each do |cat|
              xml.category cat.name
            end
            main_image = variant.external_image_url.presence || product.external_image_url
            additional_images = variant.external_image_urls.presence || product.external_image_urls || []
            if main_image.present?
              xml.enclosure url: main_image, type: "image/jpeg", length: "0"
              xml.tag! "media:content", url: main_image, medium: "image", isDefault: "true"
            end
            additional_images.each do |img_url|
              xml.tag! "media:content", url: img_url, medium: "image"
            end
          end
        end
      else
        xml.item do
          xml.title product.name
          xml.description strip_tags(product.description).to_s.truncate(500)
          xml.link product_link
          xml.guid product_link, isPermaLink: "true"
          xml.pubDate product.created_at.rfc2822
          xml.tag! "dc:creator", product.brand if product.brand.present?
          product.categories.each do |cat|
            xml.category cat.name
          end
          if product.external_image_url.present?
            xml.enclosure url: product.external_image_url, type: "image/jpeg", length: "0"
            xml.tag! "media:content", url: product.external_image_url, medium: "image", isDefault: "true"
          end
          if product.external_image_urls.present?
            product.external_image_urls.each do |img_url|
              xml.tag! "media:content", url: img_url, medium: "image"
            end
          end
        end
      end
    end
  end
end
