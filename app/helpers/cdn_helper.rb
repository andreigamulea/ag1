# app/helpers/cdn_helper.rb
module CdnHelper
  def cdn_image_url(attachment, resize: [200, 200])
    variant = attachment.variant(resize_to_limit: resize)
    key = Rails.application.routes.url_helpers.rails_representation_path(variant.processed, only_path: true)
    "https://ayus-cdn.b-cdn.net#{key}"
  end
end
