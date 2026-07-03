# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"

# The suite must never touch the network. No allowlist.
WebMock.disable_net_connect!

require "nabu"

# Shared test support: the adapter conformance suite and its test rig.
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }
