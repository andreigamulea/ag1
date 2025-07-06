# app/helpers/cdn_helper.rb
require 'faraday'
module CdnHelper
  def bunny_storage_url(attachment)
    return asset_path("placeholder.png") unless attachment&.blob&.persisted?
    key = attachment.is_a?(ActiveStorage::Variant) ? attachment.blob.key : attachment.key
    cdn_url = "https://ayus-cdn.b-cdn.net/#{key}"
    Rails.cache.fetch("cdn_url_#{key}", expires_in: 1.hour) do
      Rails.logger.debug "Generating CDN URL: #{cdn_url}"
      begin
        response = Faraday.head(cdn_url)
        if response&.status == 200
          cdn_url
        else
          Rails.logger.error "CDN URL failed (status: #{response&.status}): #{cdn_url}"
          fallback_url(attachment)
        end
      rescue Faraday::Error => e
        Rails.logger.error "Error accessing CDN URL #{cdn_url}: #{e.message}"
        fallback_url(attachment)
      end
    end
  end

  private

  def fallback_url(attachment)
    host = Rails.application.config.action_mailer.default_url_options&.[](:host) || "your-domain.com" # Înlocuiește cu domeniul tău real
    Rails.application.routes.url_helpers.rails_blob_url(attachment, host: host)
  end
end