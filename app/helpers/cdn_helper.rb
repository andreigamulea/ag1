module CdnHelper
  def bunny_storage_url(attachment)
    return asset_path("placeholder.png") unless attachment&.key.present?

    cdn_url = "https://ayus-cdn.b-cdn.net/#{attachment.key}"
    Rails.cache.fetch("cdn_url_#{attachment.key}", expires_in: 1.hour) do
      uri = URI.parse(cdn_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 2) do |http|
        http.head(uri.request_uri)
      end
      response&.code == "200" ? cdn_url : url_for(attachment)
    rescue
      url_for(attachment)
    end
  end
end