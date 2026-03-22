# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle login attempts per IP
  throttle("logins/ip", limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Throttle login attempts per email
  throttle("logins/email", limit: 5, period: 60.seconds) do |req|
    if req.path == "/users/sign_in" && req.post?
      req.params.dig("user", "email")&.downcase&.strip
    end
  end

  # Throttle coupon apply attempts (prevent brute force enumeration)
  throttle("coupons/ip", limit: 10, period: 60.seconds) do |req|
    req.ip if req.path == "/apply-coupon" && req.post?
  end

  # Throttle cart add (prevent inventory manipulation)
  throttle("cart/ip", limit: 30, period: 60.seconds) do |req|
    req.ip if req.path.start_with?("/cart") && req.post?
  end

  # Throttle registration per IP
  throttle("registrations/ip", limit: 3, period: 60.seconds) do |req|
    req.ip if req.path == "/users" && req.post?
  end

  # Throttle search per IP
  throttle("search/ip", limit: 20, period: 60.seconds) do |req|
    req.ip if req.path == "/search/index"
  end

  # Block response
  self.throttled_responder = lambda do |_env|
    [429, { "Content-Type" => "text/plain" }, ["Prea multe cereri. Încearcă din nou în câteva secunde.\n"]]
  end
end
