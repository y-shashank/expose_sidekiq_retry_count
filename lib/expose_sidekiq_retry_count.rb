# frozen_string_literal: true

require_relative "expose_sidekiq_retry_count/version"

module ExposeSidekiqRetryCount
  class Error < StandardError; end

  class ServerMiddleware
    def call(worker, job, queue)
      if worker.respond_to?(:current_retry_count=)
        worker.current_retry_count = if job['retry_count'].nil?
                                        0
                                     else
                                        job['retry_count'].to_i + 1
                                     end
      end
      if $sidekiq_redis && worker.respond_to?(:this_job_is_superfetched=)
        worker.this_job_is_superfetched = $sidekiq_redis.get("orphan-#{job['jid']}").to_i > 0
      end
      yield
    end
  end
end
