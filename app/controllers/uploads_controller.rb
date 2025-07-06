class UploadsController < ApplicationController
  def presign
    zone = ENV["BUNNY_STORAGE_ZONE"]
    api_key = ENV["BUNNY_STORAGE_API_KEY"]
    raise "Zona de stocare Bunny nu e setată" unless zone && api_key

    filename = params[:filename]
    raise "Lipsă filename" if filename.blank?

    upload_url = "https://storage.bunnycdn.com/#{zone}/#{filename}"
    render json: {
      upload_url: upload_url,
      headers: {
        "AccessKey": api_key,
        "Content-Type": "application/octet-stream"
      }
    }
  end
end
