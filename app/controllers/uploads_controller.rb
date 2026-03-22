class UploadsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin

  ALLOWED_EXTENSIONS = %w[jpg jpeg png gif webp svg pdf zip doc docx xls xlsx csv mp4 mp3].freeze

  def presign
    filename = params[:filename]
    raise "Lipsă filename" if filename.blank?

    # Sanitizare: elimină path traversal și caractere periculoase
    sanitized = File.basename(filename).gsub(/[^a-zA-Z0-9._-]/, '_')

    # Validare extensie
    ext = File.extname(sanitized).downcase.delete('.')
    unless ALLOWED_EXTENSIONS.include?(ext)
      render json: { error: "Tip de fișier nepermis: .#{ext}" }, status: :unprocessable_entity
      return
    end

    zone = ENV["BUNNY_STORAGE_ZONE"] || "ayus"
    api_key = ENV["BUNNY_STORAGE_API_KEY"] || Rails.application.credentials.dig(:bunny, :storage_key)

    upload_url = "https://storage.bunnycdn.com/#{zone}/#{sanitized}"
    render json: {
      upload_url: upload_url,
      headers: {
        "AccessKey" => api_key,
        "Content-Type" => "application/octet-stream"
      }
    }
  end
end
