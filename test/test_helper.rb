# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "expose_sidekiq_retry_count"

require "minitest/autorun"
