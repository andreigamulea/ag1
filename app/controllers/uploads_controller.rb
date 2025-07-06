# app/controllers/uploads_controller.rb
class UploadsController < ApplicationController
  def presign
  filename = params[:filename]
  zone = ENV['BUNNY_STORAGE_ZONE']
  key = ENV['BUNNY_STORAGE_API_KEY']

  upload_url = "https://storage.bunnycdn.com/#{zone}/#{filename}"
  headers = {
    "AccessKey" => key,
    "Content-Type" => "application/octet-stream"
  }

  render json: { upload_url:, headers: }
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
