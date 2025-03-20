# ExposeSidekiqRetryCount

This gem defines a sidekiq middleware which exposes the sidekiq job's retry counter value inside the job for easy access.
This gem is also accurately tracks if a job is superfetched without using any extra redis memory and this property is made easily accessible inside the job itself like the `batch` or `jid` property
Now each job will be able to access its `current_retry_count` (integer) and `this_job_is_superfetched` (boolean) property

The ability to accurately track the `superfetched` property of a particular will allow us to reduce/remove extra redis locks from application logic
It will automatically log these value inside Newrelic (if defined? ::NewRelic::Agent) for every transactions which are processed the service where this is intalled

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

Inside `ApplicationWorker` and `ApplicationJob` include the `ExposeSidekiqRetryCount::Properties` module

```
class ApplicationWorker
  include ExposeSidekiqRetryCount::Properties
end
```

STEP 3: (Optional) Set a ENV variable `EXPOSE_IF_SUPERFETCHED_IN_JOB=true`. This will inject a new property `this_job_is_superfetched` in every job which is a boolean field and it will return true if this jobs has been superfetched


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

Optional - If STEP 3 of installation is done we can use `this_job_is_superfetched` inside job

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
1. bulk_requeue - Runs on POD termination
2. check_for_orphans - Runs on POD startup
3. cleanup_the_dead - Runs on POD startup

In `check_for_orphans` `cleanup_the_dead` a LUA script runs for each jobs it recoveres and inside the script it create/increments a key inside sidekiq redis `orphan-#{jid}` we use this existing key to tell if a particular job is superfetched. The problem is with `bulk_requeue` which runs when a POD receives TERM signal and as a cleanup-step sidekiq run the following redis command in loop `conn.lmove(working_queue, queue, "RIGHT", "LEFT")` till all jobs are moved from provate queue to normal queue, but does not sets the above mentioned `orphan-#{jid}` key hence it caused problems in our tracking. So to make the tracking accurate we override this `bulk_requeue` method to do the same thing with a custom LUA script and in the script we set the `orphan-#{jid}` key with value of 0

This way we make the tracking accurate and reliable, without loosing any sidekiq in-built feature or tracking
