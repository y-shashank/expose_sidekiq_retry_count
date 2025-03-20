# frozen_string_literal: true

require_relative "expose_sidekiq_retry_count/version"
require "sidekiq/pro/scripting"

if ENV['EXPOSE_IF_SUPERFETCHED_IN_JOB']
  require "sidekiq/pro/super_fetch"
  
  module Sidekiq::Pro
    class SuperFetch
      Sidekiq::Pro::Scripting::LUA_SCRIPTS[:bulk_recover_inprogress_jobs] = <<-LUA
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

      def recover_inprogress_jobs(conn, working_queue, public_queue)
        result = Sidekiq::Pro::Scripting.call(conn, :bulk_recover_inprogress_jobs, [working_queue, public_queue], [@recovery_window], self)
      end

      # # modified
      def bulk_requeue(*)
        # Ignore the in_progress arg passed in; rpoplpush lets us know everything in process
        the_queues = queues.uniq.map { |q| ["queue:#{q}", private_queue(q)] }
        sqs = the_queues.map { |item| item[1] }
        ctn = 0
        redis do |conn|
          the_queues.each do |(queue, working_queue)|
            loop do
              jobstr = recover_inprogress_jobs(conn, working_queue, queue)
              break unless jobstr
              ctn += 1
            end
            logger.info { "SuperFetch[#{name}]: Moving job from #{working_queue} back to #{queue}" } if ctn > 0
          end
          id = identity
          _, cnt = conn.multi do |m|
            m.srem("super_processes", [id])
            m.srem("#{id}:super_queues", sqs)
          end
          logger.debug { "SuperFetch[#{name}]: Unregistered super queues #{sqs}" } if cnt > 0
        end
      rescue => ex
        # best effort, ignore Redis network errors
        logger.warn { "SuperFetch: Failed to requeue: #{ex.message}" }
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
    include Sidekiq::ServerMiddleware
    def call(worker, job, queue)
      if worker.respond_to?(:current_retry_count=)
        worker.current_retry_count = if job['retry_count'].nil?
                                        0
                                     else
                                        job['retry_count'].to_i + 1
                                     end
      end

      if $sidekiq_redis && worker.respond_to?(:this_job_is_superfetched=)
        is_superfetched = redis { |conn| conn.get("orphan-#{job['jid']}") }
        worker.this_job_is_superfetched = !is_superfetched.nil?
      end
      if defined?(::NewRelic::Agent)
        ::NewRelic::Agent.add_custom_attributes({job_retry_count: worker.current_retry_count, superfetched: worker.this_job_is_superfetched}) rescue nil
      end
      yield
    end
  end
end
