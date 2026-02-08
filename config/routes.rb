# config/routes.rb
Rails.application.routes.draw do
  get 'search/index'

  get 'newsletter', to: 'home#newsletter'
  post '/newsletter', to: 'home#newsletter'
  get 'home/lista_newsletter', to: 'home#lista_newsletter', as: 'lista_newsletter'
  get 'home/newsletter/:id/edit', to: 'home#edit_newsletter', as: 'edit_newsletter' 
  patch 'home/newsletter/:id', to: 'home#update_newsletter', as: 'update_newsletter' 
  delete 'home/newsletter/:id', to: 'home#delete_newsletter', as: 'delete_newsletter'

  post '/stripe/webhooks', to: 'stripe_webhooks#create'

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

  resources :orders, only: [:index, :new, :create] do
    member do
      get :show_items
      get :invoice
    end
    collection do
      get :thank_you
      get :success, as: :success
    end
  end

  get "/uploads/presign", to: "uploads#presign"
  post "/uploads/presign", to: "uploads#presign" 
  post "/uploads/upload_bunny", to: "uploads#upload_bunny"

  get 'memory_logs/index'
  
  # Autentificare Devise cu controller custom (fără modul Users::)
  devise_for :users, controllers: {
    registrations: 'custom_registrations'
  }
  
  # Rută personalizată pentru dezactivare
  devise_scope :user do
    patch 'users/deactivate', to: 'custom_registrations#deactivate', as: 'deactivate_user_registration'
  end
  
  # Rute pentru administrarea utilizatorilor
  # Rute pentru administrarea utilizatorilor
resources :users, except: [:edit, :update] do
  member do
    get 'admin_edit', to: 'users#edit', as: 'admin_edit'
    patch 'admin_update', to: 'users#update', as: 'admin_update'
    patch :reactivate
  end
end
  
  resources :carti, only: [:index, :show], param: :slug

  get "/mem", to: "monitoring#mem", as: :mem
  get "/ram_logs", to: "memory_logs#index", as: :ram_logs
  post "simulate_gc", to: "products#simulate_memory_usage_and_gc", as: :simulate_memory_usage_and_gc
  get "/cdn/:signed_id", to: "cdn_proxy#proxy", as: :cdn_proxy

  get '/products/force_gc', to: 'products#force_gc', as: 'force_gc_products'
  
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
  get 'politica-confidentialitate', to: 'home#politica_confidentialitate', as: :politica_confidentialitate
  get 'politica-cookies', to: 'home#politica_cookies', as: :politica_cookies
  get 'termeni-si-conditii', to: 'home#termeni_conditii', as: :termeni_conditii
  get 'up' => 'rails/health#show', as: :rails_health_check

  root 'home#index'
end