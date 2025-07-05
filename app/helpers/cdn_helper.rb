# app/helpers/cdn_helper.rb
module CdnHelper
  def bunny_storage_url(attachment)
    return asset_path("placeholder.png") unless attachment&.blob&.persisted?
    key = attachment.is_a?(ActiveStorage::Variant) ? attachment.blob.key : attachment.key
    cdn_url = "https://ayus-cdn.b-cdn.net/#{key}"
    Rails.cache.fetch("cdn_url_#{key}", expires_in: 1.hour) do
      Rails.logger.debug "Generating CDN URL: #{cdn_url}"
      begin
        response = Faraday.head(cdn_url)
        response&.code == "200" ? cdn_url : url_for(attachment)
      rescue
        url_for(attachment)
      end
    end
  end
end