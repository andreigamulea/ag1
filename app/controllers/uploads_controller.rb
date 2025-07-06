class UploadsController < ApplicationController
  def presign
    filename = params[:filename].parameterize.truncate(100, omission: "")
    zone = ENV["BUNNY_STORAGE_ZONE"] || "ayus"
    upload_url = "https://storage.bunnycdn.com/#{zone}/uploads/#{filename}"

    render json: {
      upload_url: upload_url,
      headers: {
        "AccessKey" => ENV["BUNNY_STORAGE_KEY"],
        "Content-Type" => "application/octet-stream"
      }
    }
  end
end
