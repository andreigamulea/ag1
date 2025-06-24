Rails.application.routes.draw do
  # Autentificare Devise (înainte de orice alte rute care pot intra în conflict)
  devise_for :users

  # Rute RESTful pentru administrarea utilizatorilor și produse
  resources :users
  resources :products do
    member do
      delete 'purge_image/:image_id', to: 'products#purge_image', as: :purge_image
      delete 'purge_main_image', to: 'products#purge_main_image', as: :purge_main_image
    end
  end



  # Pagini custom
  get 'admin', to: 'home#admin'
  get 'home/index'
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Rădăcina aplicației
  root 'home#index'
end
