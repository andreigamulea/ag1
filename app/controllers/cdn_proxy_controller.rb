# app/controllers/cdn_proxy_controller.rb
class CdnProxyController < ApplicationController
  include ActiveStorage::SetCurrent
  include ActiveStorage::DownloadHelper

  def proxy
    blob = ActiveStorage::Blob.find_signed(params[:signed_id])
    redirect_to rails_blob_representation_url(blob, only_path: false, disposition: "inline", resize_to_limit: [800, 800])
  end
end
