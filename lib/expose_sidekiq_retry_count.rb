# frozen_string_literal: true

require_relative "expose_sidekiq_retry_count/version"

module ExposeSidekiqRetryCount
  class Error < StandardError; end
  # Your code goes here...

  class ServerMiddleware
    def call(worker, job, queue)
      worker.current_retry_count = job['retry_count'] if worker.respond_to?(:retry_count=)
      yield
    end
  end
end
