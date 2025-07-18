class LocationsController < ApplicationController
  def judete
    tara = Tari.find_by(nume: params[:tara])
    judete = tara ? Judet.where(tari_id: tara.id).order(:nume) : []
    render json: judete.select(:nume)
  end

  def localitati
    judet = Judet.find_by(nume: params[:judet])
    localitati = judet ? Localitate.where(judet_id: judet.id).order(:nume) : []
    render json: localitati.select(:nume)
  end
end
