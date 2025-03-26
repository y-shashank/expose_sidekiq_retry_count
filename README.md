# ExposeSidekiqRetryCount

This gem defines a sidekiq middleware which exposes the sidekiq job's retry counter value inside the job for easy access.
This gem is also accurately tracks if a job is superfetched without using any extra redis memory and this property is made easily accessible inside the job itself like the `batch` or `jid` property
Now each job will be able to access its `current_retry_count` (integer) and `this_job_is_superfetched` (boolean) property

The ability to accurately track the `superfetched` property of a particular will allow us to reduce/remove extra redis locks from application logic
It will automatically log these value inside Newrelic (if defined? ::NewRelic::Agent) for every transactions which are processed the service where this is intalled

## Installation

STEP 1: In gemfile add the follwing gem and run bundle install

```
gem 'expose_sidekiq_retry_count', git: 'https://github.com/y-shashank/expose_sidekiq_retry_count'
```
OR
```
gem 'expose_sidekiq_retry_count', git: 'https://github.com/y-shashank/expose_sidekiq_retry_count', tag: '1.0.0'
```


STEP 2: Add the following middleware inside `sidekiq.rb`

```

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add ExposeSidekiqRetryCount::ServerMiddleware
  end
end

```

Inside `ApplicationWorker` and `ApplicationJob` include the `ExposeSidekiqRetryCount::Properties` module

```
class ApplicationWorker
  include ExposeSidekiqRetryCount::Properties
end
```

STEP 3: (Optional) Set a ENV variable `EXPOSE_IF_SUPERFETCHED_IN_JOB=true`. This will inject a new boolean property `this_job_is_superfetched` in every job and it will return `true` if this jobs has been superfetched else `false`. If this step is not done then `this_job_is_superfetched` will accessible but it will always retrun `nil`.


## Usage

Inside any job you can access `current_retry_count` directly

```
class BulkRewardMakingWorker < ApplicationWorker
  def perform
    if current_retry_count == 0
      # no need to check for duplicate gifting
    elsif !this_job_is_superfetched # Complete STEP-3 of Installation
      # no need to check for duplicate gifting
    else
      # check for double gifting
    end
  end
end
```

# Sidekiq SuperFetch Internals

There are 3 methods inside superfetch from where we move jobs from private queues back to normal queues
1. bulk_requeue - Runs on POD termination
2. check_for_orphans - Runs on POD startup
3. cleanup_the_dead - Runs on POD startup

In `check_for_orphans` `cleanup_the_dead` a LUA script runs for each jobs it recoveres. Inside the script it create/increments a key inside sidekiq redis `orphan-#{jid}` (1 -> 2 ->3 -> Poison Kill) we use this existing key to tell if a particular job is superfetched. The problem is with `bulk_requeue` is that it only runs when a POD receives TERM signal and as a cleanup-step sidekiq run the following redis command in loop `conn.lmove(working_queue, queue, "RIGHT", "LEFT")` till all jobs are moved from provate queue to normal queue, but does not sets the above mentioned `orphan-#{jid}` key hence it caused problems in our tracking. So to make the tracking accurate we override this `bulk_requeue` method to do the same thing with a custom LUA script and in the script we set the `orphan-#{jid}` key with value of 0 if key doesnt exist but if the key exist from before we dont do inc/dec this key and let sidekiq maintain its lifecycle.

This way we make the tracking 100% accurate and reliable, without loosing any sidekiq in-built feature or tracking.

# LUA script added for bulk_requeue

```
LUA
  local jobstr = redis.call('lindex', KEYS[1], -1)
  if not jobstr then
    return nil
  end
  local result, job = pcall(cjson.decode, jobstr)
  if not result then
    return redis.call('lmove', KEYS[1], KEYS[2], 'right', 'left')
  end

  if redis.call('get', 'orphan-'..job.jid) then

  else
    redis.call('set', 'orphan-'..job.jid, 0)
    redis.call('expire', 'orphan-'..job.jid, ARGV[1])
  end
  return redis.call('lmove', KEYS[1], KEYS[2], 'right', 'left')
LUA
```
