#!/usr/bin/env bash
set -o errexit

echo "🔧 Instalez ImageMagick pentru variant thumbnails..."
apt-get update && apt-get install -y imagemagick

echo "🧹 Curățare cache vechi..."
rm -rf tmp/cache

echo "📦 Instalez gem-uri..."
bundle install

echo "📁 Creez directorul pentru fișiere Active Storage..."
mkdir -p /var/data/storage

echo "🧱 Precompilez assets (Importmap)..."
bundle exec rake assets:precompile

echo "🗄 Migrez baza de date..."
bundle exec rake db:migrate

echo "✅ Build finalizat cu succes!"
