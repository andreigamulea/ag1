module ApplicationHelper
  # Domeniul canonical pentru SEO - dinamic pe bază de Rails environment
  # Production: ayus.ro | Development/Staging: ag1-eef1.onrender.com
  def canonical_host
    if Rails.env.production?
      "https://ayus.ro"
    else
      "https://ag1-eef1.onrender.com"
    end
  end
end
