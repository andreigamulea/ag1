class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  before_action :set_user, only: %i[show edit update destroy reactivate]

  def index
    @users = User.all.order(:id)
  end

  def show
  end

  def edit
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to users_path, notice: "Utilizatorul a fost creat."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @user.update(user_params)
      redirect_to users_path, notice: "Utilizatorul a fost actualizat cu succes."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "Nu poți șterge propriul cont."
    else
      @user.destroy
      redirect_to users_path, notice: "Utilizatorul a fost șters."
    end
  end

  def reactivate
    if @user.reactivate!
      redirect_to users_path, notice: "Contul utilizatorului #{@user.email} a fost reactivat cu succes."
    else
      redirect_to users_path, alert: "Eroare la reactivarea contului."
    end
  end

  private

  def authorize_admin!
    redirect_to root_path, alert: "Acces interzis!" unless current_user&.role == 1
  end

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
  params.require(:user).permit(:email, :password, :password_confirmation, :role, :active)
end
end