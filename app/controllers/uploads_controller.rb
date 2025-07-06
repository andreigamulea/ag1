class UploadsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def presign
    filename = params[:filename]
    zone = ENV["BUNNY_STORAGE_ZONE"]
    key = ENV["BUNNY_STORAGE_API_KEY"]

    upload_url = "https://storage.bunnycdn.com/#{zone}/#{filename}"

    headers = {
      "AccessKey" => key,
      "Content-Type" => Rack::Mime.mime_type(File.extname(filename))
    }

    render json: {
      upload_url: upload_url,
      headers: headers
    }
  end
end
