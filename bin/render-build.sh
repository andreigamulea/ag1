#!/usr/bin/env bash
set -o errexit

echo "🔧 Instalez libvips pentru thumbnails ActiveStorage (rapid și low RAM)..."
apt-get update -qq && apt-get install -y -qq libvips
apt-get clean && rm -rf /var/lib/apt/lists/*

echo "🧹 Curățare cache vechi..."
rm -rf tmp/cache public/assets storage/variants

echo "📦 Instalez gem-urile necesare doar pentru producție..."
bundle install --without development test --jobs 4 --retry 3

# Dacă ai Yarn/ESBuild, adaugă aici:
# yarn install --frozen-lockfile

echo "📁 Creez directorul pentru fișiere Active Storage (dacă nu există)..."
mkdir -p /var/data/storage

echo "🧱 Precompilez assets (importmap / css / turbo)..."
bundle exec rake assets:precompile

echo "🗄 Migrez baza de date (dacă sunt modificări)..."
bundle exec rake db:migrate || true

echo "✅ Build finalizat cu succes!"