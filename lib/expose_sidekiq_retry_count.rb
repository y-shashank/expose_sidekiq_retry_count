# frozen_string_literal: true

require_relative "expose_sidekiq_retry_count/version"

if ENV['EXPOSE_IF_SUPERFETCHED_IN_JOB']
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
end

module ExposeSidekiqRetryCount
  class Error < StandardError; end

  module Properties
    attr_accessor :current_retry_count
    def current_retry_count
      @current_retry_count || 0
    end

    if ENV['EXPOSE_IF_SUPERFETCHED_IN_JOB']
      attr_accessor :this_job_is_superfetched

      def this_job_is_superfetched
        @this_job_is_superfetched || false
      end
    end
  end


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
      ::NewRelic::Agent.add_custom_attributes({job_retry_count: worker.current_retry_count, superfetched: worker.this_job_is_superfetched}) rescue nil
      yield
    end
  end
end
