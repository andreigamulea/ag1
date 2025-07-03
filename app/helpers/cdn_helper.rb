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
end
