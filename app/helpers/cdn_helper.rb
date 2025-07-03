# app/helpers/cdn_helper.rb
module CdnHelper
  def bunny_cdn_url(attachment)
    return asset_path("fallbacks/no-image.jpg") unless attachment.attached?

    key = attachment.key
    filename = attachment.filename.to_s

    if Rails.env.production?
      "https://ayus-cdn.b-cdn.net/#{key}/#{filename}"
    else
      url_for(attachment)
    end
  end
end
