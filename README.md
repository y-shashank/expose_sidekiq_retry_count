# ExposeSidekiqRetryCount

This gem defines a sidekiq middleware which exposes the sidekiq job's retry counter value inside the job for easy access.
This gem is also accurately tracks if a job is superfetched without using any extra redis memory and this property is made easily accessible inside the job itself like the `batch` or `jid` property
Now each job will be able to access its `current_retry_count` (integer) and `this_job_is_superfetched` (boolean) property

The ability to accurately track the `superfetched` property of a particular will allow us to reduce/remove extra redis locks from application logic

## Installation

STEP 1: In gemfile add the follwing gem and run bundle install

```
gem 'expose_sidekiq_retry_count', git: 'https://github.com/punchh/expose_sidekiq_retry_count'
```
OR
```
gem 'expose_sidekiq_retry_count', git: 'https://github.com/punchh/expose_sidekiq_retry_count', tag: '1.0.0'
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

Inside `initializers/redis.rb`

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

Inside `initializers/sidekiq.rb`

```
require "sidekiq/pro/super_fetch"

module Sidekiq::Pro
  class SuperFetch
    def bulk_requeue(*)
      # we dont want this method to do anything
      # this runs when TERM singal is received by sidekiq pod
      # if we dont override this method then :this_job_is_superfetched accessor is not reliable
    end
  end
end
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

# Sidekiq SuperFetch Internals

There are 3 methods inside superfetch from where we move jobs from private queues back to normal queues
1. bulk_requeue
2. check_for_orphans
3. cleanup_the_dead

In `check_for_orphans` `cleanup_the_dead` a LUA script runs for each jobs it recoveres and inside the script it create/increments a key inside sidekiq redis `orphan-#{jid}` we use this existing key to tell if a particular job is superfetched. The problem is with `bulk_requeue` which runs when a POD receives TERM signal and as a cleanup-step sidekiq run the following redis command in loop `conn.lmove(working_queue, queue, "RIGHT", "LEFT")` till all jobs are moved from provate queue to normal queue, but does not sets the above mentioned `orphan-#{jid}` key hence it caused problems in our tracking. So to make the tracking accurate we override this `bulk_requeue` method to do nothing. Hence all orphan jobs are recovered using `check_for_orphans` `cleanup_the_dead` methods which should be fine as the LUA sciprt interally uses the same LMOVE command.

This way we make the tracking accurate and reliable

