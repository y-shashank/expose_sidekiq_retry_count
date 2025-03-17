# frozen_string_literal: true

require_relative "expose_sidekiq_retry_count/version"

module ExposeSidekiqRetryCount
  class Error < StandardError; end
  # Your code goes here...

  class ServerMiddleware
    def call(worker, job, queue)
      if worker.respond_to?(:current_retry_count=)
        worker.current_retry_count = if job['retry_count'].nil?
                                        0
                                     else
                                        job['retry_count'].to_i + 1
                                     end
      end
      yield
    end
  end
end
