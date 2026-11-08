if Rails.env.test?
  data_store = Stoplight::DataStore::Memory.new
else
  redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379")
  begin
    redis.ping
    data_store = Stoplight::DataStore::Redis.new(redis)
  rescue StandardError => e
    # Fall back to a per-process in-memory store so lookups keep working when
    # redis is not running (local dev, runners). Circuit state becomes
    # per-process, which is acceptable.
    Rails.logger.warn("Stoplight: redis unavailable (#{e.class}: #{e.message}); using memory data store")
    data_store = Stoplight::DataStore::Memory.new
  end
end

Stoplight.configure do |config|
  config.data_store = data_store
  config.notifiers += [ Stoplight::Notifier::Logger.new(Rails.logger) ]
end

Stoplight::Admin.set :host_authorization, { permitted_hosts: [ ENV["APP_DOMAIN"], "localhost" ].compact }
