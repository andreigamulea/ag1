max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 2 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { 1 }
threads min_threads_count, max_threads_count

rails_env = ENV.fetch("RAILS_ENV") { "development" }
environment rails_env

port ENV.fetch("PORT") { 3000 }
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

worker_timeout 30 if rails_env == "production"

if rails_env == "production"
  worker_count = Integer(ENV.fetch("WEB_CONCURRENCY") { 1 })
  preload_app!  # FORȚAT pentru economie de memorie
  workers worker_count if worker_count > 1
end

plugin :tmp_restart
