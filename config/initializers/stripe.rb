if Rails.env.development?
    Stripe.api_key = Rails.application.credentials.dig(:stripe, :development, :secret_key) || ENV['STRIPE_SECRET_KEY']
  elsif Rails.env.production?
    Stripe.api_key = Rails.application.credentials.dig(:stripe, :production, :secret_key) || ENV['STRIPE_SECRET_KEY']
  end
  
