# syntax = docker/dockerfile:1

# Set Ruby version — as in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.7
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Set working directory
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

# ---------------- BUILD STAGE ----------------
FROM base AS build


# Install packages needed to build native gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libpq-dev \
    libvips \
    libyaml-dev \       # ← adăugat pentru psych
    pkg-config

# Copy gemfiles and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy rest of the app
COPY . .

# Precompile bootsnap to speed up runtime
RUN bundle exec bootsnap precompile app/ lib/

# Make sure bin/ scripts are executable and UNIX-style
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# Precompile assets (skip master key requirement by setting dummy secret)
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ---------------- FINAL IMAGE ----------------
FROM base

# Install only runtime dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    curl \
    libvips \
    postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built app and gems
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Create app user and assign ownership
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp

USER rails:rails

# Entrypoint prepares database
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Expose port and start server by default
EXPOSE 3000
CMD ["./bin/rails", "server"]
