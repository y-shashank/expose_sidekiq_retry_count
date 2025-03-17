# ExposeSidekiqRetryCount

This gem defines a sidekiq middleware which exposes the sidekiq job's retry counter value inside the job for easy access.
Similar to accessor `batch` it can be accessed anywhere inside job

## Installation

STEP 1: In gemfile add the follwing gem and run bundle install

```
gem 'expose_sidekiq_retry_count', git: 'https://github.com/punchh/expose_sidekiq_retry_count'
```

STEP 2: Add the following middleware inside `sidekiq.rb`

```

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ExposeSidekiqRetryCount::ServerMiddleware
  end
end

```

STEP 3: Inside `ApplicationWorker` add define the following accssor and method so its available to all sidekiq jobs

```
class ApplicationWorker
  include Sidekiq::Worker
  attr_accessor :current_retry_count

  def current_retry_count
    @current_retry_count || 0
  end
end

```

STEP 4: (Optional) Define global `$sidekiq_redis` redis connection to sidekiq redis inside a initializer. This will inject a new property `this_job_is_superfetched` in every job which is a boolean field and it will return true if this jobs has been superfetched

```
class RedisSetup
  def self.setup(redis_config)
    redis = Redis.new(host: redis_config[:host],
                  port: redis_config[:port],
                  driver: redis_config[:driver].to_sym,
                  password: redis_config[:password],
                  reconnect_attempts: 10)
    Redis::Namespace.new(redis_config[:namespace], redis: redis)
  end
end

$sidekiq_redis = RedisSetup.setup($redis_configs[:sidekiq])
```


## Usage

Inside any job you can access `current_retry_count` directly

```
class BulkRewardMakingWorker < ApplicationWorker
    def perform
        if current_retry_count == 0
            # no need to check for duplicate gifting
        else
            # check for double gifting
        end
    end
end
```

Optional - If STEP 4 of installation is done

```
class BulkRewardMakingWorker < ApplicationWorker
    def perform
        if !this_job_is_superfetched
            # no need to check for duplicate gifting
        else
            # check for double gifting
        end
    end
end
```
