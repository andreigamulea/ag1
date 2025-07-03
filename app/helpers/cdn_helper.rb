module CdnHelper
  require 'net/http'
  require 'uri'

  def bunny_storage_url(attachment)
    return asset_path("fallbacks/no-image.jpg") unless attachment&.key.present?

    cdn_url = "https://ayus-cdn.b-cdn.net/#{attachment.key}"

    # Verifică rapid dacă CDN-ul servește imaginea (HEAD request)
    uri = URI.parse(cdn_url)
    response = nil
    begin
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.head(uri.request_uri)
      end
    rescue
      response = nil
    end

    if response&.code == "200"
      cdn_url
    else
      # fallback la url-ul temporar generat de ActiveStorage (semnat)
      url_for(attachment)
    end
  end
end
