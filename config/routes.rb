Rails.application.routes.draw do
  # Autentificare Devise (înainte de orice alte rute care pot intra în conflict)
  devise_for :users
  # Rute RESTful pentru administrarea utilizatorilor și produse
  resources :carti, only: [:index, :show]

  get "/mem", to: "monitoring#mem", as: :mem




  resources :users
  resources :products do
  member do
    delete 'purge_image/:image_id', to: 'products#purge_image', as: :purge_image
    delete 'purge_main_image', to: 'products#purge_main_image', as: :purge_main_image
    delete :purge_attached_file
    
    get :new_category
    post :create_category
    get :edit_categories
    patch :update_categories
  end

  collection do
  get :categories_index
  get :new_standalone_category
  get :show_standalone_category
  post :create_standalone_category
  get :edit_standalone_category
  patch :update_standalone_category
  delete :delete_standalone_category
end


end


  # Pagini custom
  get 'admin', to: 'home#admin'
  get 'home/index'
  get 'contact', to: 'home#contact'
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Rădăcina aplicației
  root 'home#index'
end
