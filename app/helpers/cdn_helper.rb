module CdnHelper
  def cdn_image_url(attachment, resize: [200, 200])
    variant = attachment.variant(resize_to_limit: resize)

    if Rails.env.production?
      key = Rails.application.routes.url_helpers.rails_representation_path(
        variant.processed, only_path: true
      )
      "https://ayus-cdn.b-cdn.net#{key}"
    else
      # Pe local, folosește direct url_for
      url_for(variant)
    end
  end
  
  def cdn_image_url(attachment, resize: [300, 300])
    return asset_path("fallbacks/no-image.jpg") unless attachment.present?

    url = rails_representation_url(
      attachment.variant(resize_to_limit: resize).processed,
      only_path: false
    )

    if Rails.env.production?
      url.gsub("https://ag1-eef1.onrender.com", "https://ayus-cdn.b-cdn.net")
    else
      url
    end
  end

end
