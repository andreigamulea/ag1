module CdnHelper
  def bunny_storage_url(attachment)
    return asset_path("fallbacks/no-image.jpg") unless attachment.present? && attachment.key


    original_url = url_for(attachment)

    "https://ayus.b-cdn.net/#{attachment.key}/#{attachment.filename}"
  end
end
