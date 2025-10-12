#Stripe.api_key = Rails.application.credentials.stripe[:secret_key]
if Rails.env.development?
    Stripe.api_key = Rails.application.credentials.dig(:stripe, :development, :secret_key)
  elsif Rails.env.production?
    Stripe.api_key = Rails.application.credentials.dig(:stripe, :production, :secret_key)
  end
  
