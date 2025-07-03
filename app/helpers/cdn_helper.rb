module CdnHelper
  def bunny_cdn_url(attachment)
    return asset_path("fallbacks/no-image.jpg") unless attachment&.attached?

    original_url = url_for(attachment)

    if Rails.env.production?
      original_url.gsub("https://ag1-eef1.onrender.com", "https://ayus-cdn.b-cdn.net")
    else
      original_url
    end
  end
end
