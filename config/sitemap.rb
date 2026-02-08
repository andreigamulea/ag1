# Set the host name for URL creation
# Production: uses SITE_URL env var or defaults to ayus.ro
# Development: defaults to ag1-eef1.onrender.com
# Instructions: On Render deployment, set SITE_URL=https://ayus.ro
SitemapGenerator::Sitemap.default_host = if Rails.env.production?
  ENV.fetch('SITE_URL', 'https://ayus.ro')
else
  ENV.fetch('SITE_URL', 'https://ag1-eef1.onrender.com')
end

# Pick a place safe to write the files
SitemapGenerator::Sitemap.public_path = 'public/'

# Store on S3 (optional, comment out if not needed)
# SitemapGenerator::Sitemap.adapter = SitemapGenerator::S3Adapter.new(
#   fog_provider: 'AWS',
#   aws_access_key_id: ENV['AWS_ACCESS_KEY_ID'],
#   aws_secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
#   fog_directory: ENV['S3_BUCKET_NAME'],
#   fog_region: ENV['AWS_REGION']
# )

# Inform the map cross-referenced urls for your host
# SitemapGenerator::Sitemap.sitemaps_host = "https://s3.amazonaws.com/#{ENV['S3_BUCKET_NAME']}/"

SitemapGenerator::Sitemap.create do
  # Put links creation logic here.
  #
  # The root path '/' and sitemap index file are added automatically for you.
  # Links are added to the Sitemap in the order they are specified.
  #
  # Usage: add(path, options={})
  #        (default options are used if you don't specify)
  #
  # Defaults: :priority => 0.5, :changefreq => 'weekly',
  #           :lastmod => Time.now, :host => default_host
  #
  # Examples:
  #
  # Add '/articles'
  #
  #   add articles_path, :priority => 0.7, :changefreq => 'daily'
  #
  # Add all articles:
  #
  #   Article.find_each do |article|
  #     add article_path(article), :lastmod => article.updated_at
  #   end

  # ========================================
  # PAGINI STATICE
  # ========================================
  
  # Homepage (adaugata automat, dar o specificam pentru priority)
  add root_path, priority: 1.0, changefreq: 'daily'
  
  # Contact
  add contact_path, priority: 0.8, changefreq: 'monthly'
  
  # Pagina carti/produse publice
  add carti_index_path, priority: 0.9, changefreq: 'weekly'
  
  # ========================================
  # PAGINI LEGALE
  # ========================================
  
  add politica_confidentialitate_path, priority: 0.3, changefreq: 'yearly'
  add politica_cookies_path, priority: 0.3, changefreq: 'yearly'
  add termeni_conditii_path, priority: 0.3, changefreq: 'yearly'
  
  # ========================================
  # PRODUSE DINAMICE
  # ========================================
  
  # Adauga toate produsele publice (active)
  Product.where(status: 'active').find_each do |product|
    images = []
    images << { loc: product.external_image_url, title: product.name } if product.external_image_url.present?

    add carti_path(product),
        priority: 0.8,
        changefreq: 'weekly',
        lastmod: product.updated_at,
        images: images
  end

  # ========================================
  # CATEGORII DINAMICE
  # ========================================

  Category.find_each do |category|
    add carti_index_path(category: category.slug),
        priority: 0.7,
        changefreq: 'weekly',
        lastmod: category.updated_at
  end
end
