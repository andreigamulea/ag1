Rails.application.routes.draw do
  #get 'locations/judete', to: 'locations#judete'
  #get 'locations/localitati', to: 'locations#localitati'

get '/autocomplete_tara', to: 'orders#autocomplete_tara'
get '/autocomplete_judet', to: 'orders#autocomplete_judet'
get '/autocomplete_localitate', to: 'orders#autocomplete_localitate'




 post "/apply-coupon", to: "cart#apply_coupon", as: :apply_coupon
 post "/remove-coupon", to: "cart#remove_coupon", as: :remove_coupon
resources :coupons

  resources :cart, only: [:index] do
    post :add, on: :collection
    post :update, on: :collection
    post :update_all, on: :collection
    post :remove, on: :collection
    post :clear, on: :collection
  end

  resources :orders, only: [:new, :create] do
    get :thank_you, on: :collection
  end




  get "/uploads/presign", to: "uploads#presign"
  post "/uploads/presign", to: "uploads#presign" 
  post "/uploads/upload_bunny", to: "uploads#upload_bunny"
  



  get 'memory_logs/index'
  # Autentificare Devise (înainte de orice alte rute care pot intra în conflict)
  devise_for :users
  # Rute RESTful pentru administrarea utilizatorilor și produse
  resources :carti, only: [:index, :show]

  get "/mem", to: "monitoring#mem", as: :mem
  get "/ram_logs", to: "memory_logs#index", as: :ram_logs
post "simulate_gc", to: "products#simulate_memory_usage_and_gc", as: :simulate_memory_usage_and_gc
get "/cdn/:signed_id", to: "cdn_proxy#proxy", as: :cdn_proxy


get '/products/force_gc', to: 'products#force_gc', as: 'force_gc_products'



  resources :users
  resources :products do
  member do
    delete 'purge_image/:image_id', to: 'products#purge_image', as: :purge_image
    delete 'purge_main_image', to: 'products#purge_main_image', as: :purge_main_image
    delete :purge_attached_file
    delete :purge_external_file
    
    get :new_category
    post :create_category
    get :edit_categories
    patch :update_categories
  end

  collection do
    post :force_gc
  #post :force_gc # va apela metoda `force_gc` din controller
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
