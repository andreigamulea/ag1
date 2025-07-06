# app/services/bunny_cdn_service.rb
class BunnyCdnService
  STORAGE_ZONE = "ayus"
  API_KEY = ENV["BUNNY_STORAGE_API_KEY"]

  def self.presign_put_url(key:, content_type:)
    {
      url: "https://storage.bunnycdn.com/#{STORAGE_ZONE}/#{key}",
      headers: {
        "AccessKey" => API_KEY,
        "Content-Type" => content_type
      }
    }
  end
end
