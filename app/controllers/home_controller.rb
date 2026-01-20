class HomeController < ApplicationController
  before_action :authenticate_user!, only: [:admin]
  before_action :check_admin, only: [:admin, :lista_newsletter, :edit_newsletter, :update_newsletter, :delete_newsletter]

  def index
  end
  
  def admin
    # panou admin
  end
  
  def contact
    # pagina de contact
  end

  def politica_confidentialitate
  end

  def politica_cookies
  end

  def termeni_conditii
  end

  def newsletter #este o metoda de tip POST
    Rails.logger.debug "Params: #{params.inspect}"
   
    newsletter = Newsletter.new(newsletter_params)
    if newsletter.save
      render json: { message: "Înscriere reușită!" }, status: :created
    else
      render json: { errors: newsletter.errors.full_messages }, status: :unprocessable_entity
    end
  end
     
  def lista_newsletter #afiseaza pe cei inscrisi
    if current_user && current_user.role == 1
      @lista = Newsletter.order(created_at: :desc)
      @n = 0
      @nr_inscrisi = @lista.count
    else
      redirect_to root_path, alert: "Nu ai permisiunea să accesezi această pagină."
    end
  end
  
  def edit_newsletter
    if current_user && current_user.role == 1
      @newsletter = Newsletter.find(params[:id])
    else
      redirect_to root_path, alert: "Nu ai permisiunea să accesezi această pagină."
    end
  end
  
  def update_newsletter
    if current_user && current_user.role == 1
      @newsletter = Newsletter.find(params[:id])
      if @newsletter.update(newsletter_params)
        redirect_to lista_newsletter_path, notice: "Abonatul a fost actualizat cu succes!"
      else
        render :edit_newsletter
      end
    else
      redirect_to root_path, alert: "Nu ai permisiunea să efectuezi această acțiune."
    end
  end
  
  def delete_newsletter
    if current_user && current_user.role == 1
      @newsletter = Newsletter.find(params[:id])
      @newsletter.destroy
      redirect_to lista_newsletter_path, notice: "Abonatul a fost șters cu succes!"
    else
      redirect_to root_path, alert: "Nu ai permisiunea să efectuezi această acțiune."
    end
  end
     
  private
     
  def newsletter_params
    params.require(:newsletter).permit(:nume, :email, :validat)
  end

  def check_admin
    unless current_user&.role == 1
      redirect_to root_path, alert: "Nu ai permisiunea să accesezi această pagină."
    end
  end
end