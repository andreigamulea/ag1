#!/usr/bin/env bash
set -o errexit

echo "🔧 Instalez libvips pentru ActiveStorage & variant thumbnails..."
apt-get update -qq && apt-get install -y -qq libvips

echo "🧹 Curăț cache vechi..."
rm -rf tmp/cache

echo "📦 Instalez gem-urile necesare pentru producție..."
bundle install --without development test --jobs 4 --retry 3

echo "📁 Creez directorul pentru fișiere ActiveStorage..."
mkdir -p /var/data/storage

echo "🧱 Precompilez assets..."
bundle exec rake assets:precompile

echo "🗄 Migrez baza de date..."
bundle exec rake db:migrate

echo "✅ Build finalizat cu succes!"
