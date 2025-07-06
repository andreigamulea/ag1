class UploadsController < ApplicationController
 def presign
  filename = params[:filename]
  raise "Lipsă filename" if filename.blank?

  zone = ENV["BUNNY_STORAGE_ZONE"] || "ayus"
  api_key = ENV["BUNNY_STORAGE_API_KEY"] || Rails.application.credentials.dig(:bunny, :storage_key)

  upload_url = "https://storage.bunnycdn.com/#{zone}/#{filename}"
  render json: {
    upload_url: upload_url,
    headers: {
      "AccessKey" => api_key,
      "Content-Type" => "application/octet-stream"
    }
  }
end

end
