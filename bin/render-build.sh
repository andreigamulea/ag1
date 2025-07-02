#!/usr/bin/env bash
set -o errexit

echo "🔧 Instalez libvips pentru thumbnails ActiveStorage (rapid și low RAM)..."
apt-get update -qq && apt-get install -y -qq libvips

echo "🧹 Curățare cache vechi..."
rm -rf tmp/cache
rm -rf public/assets
rm -rf storage/variants

echo "📦 Instalez gem-urile necesare doar pentru producție..."
bundle install --without development test --jobs 4 --retry 3

echo "📁 Creez directorul pentru fișiere Active Storage (dacă nu există)..."
mkdir -p /var/data/storage

echo "🧱 Precompilez assets (importmap / css / turbo)..."
bundle exec rake assets:precompile

echo "🗄 Migrez baza de date (dacă sunt modificări)..."
bundle exec rake db:migrate

echo "✅ Build finalizat cu succes!"
