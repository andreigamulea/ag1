# app/controllers/uploads_controller.rb
class UploadsController < ApplicationController
  def presign
  filename = params[:filename]
  extension = File.extname(filename).downcase
  mime = Rack::Mime.mime_type(extension)

  upload_url = "https://storage.bunnycdn.com/#{ENV["BUNNY_STORAGE_ZONE"]}/#{filename}?AccessKey=#{ENV["BUNNY_STORAGE_API_KEY"]}"

  render json: {
    upload_url: upload_url,
    headers: {
      "Content-Type": mime || "application/octet-stream"
    }
  }
end


  private

  def mime_type(filename)
    case File.extname(filename).downcase
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".gif" then "image/gif"
    else "application/octet-stream"
    end
  end
end
