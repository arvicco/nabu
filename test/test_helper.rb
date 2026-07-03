# frozen_string_literal: true

require "minitest/autorun"
require "webmock/minitest"

# The suite must never touch the network. No allowlist.
WebMock.disable_net_connect!

require "nabu"
