# frozen_string_literal: true

# The suite's stand-in for script/embed_worker.py (P93-4): speaks the
# exact worker protocol (ready line, then JSONL request/response) with a
# deterministic toy encoder, so Embed tests exercise the real
# Shell.duplex plumbing with no Python, no venv, no model — the
# enricher-tests-stub-model-calls rule at subprocess grain (the P84-1
# fake-worker precedent).
#
# Toy encoding: dim 4, int8 like production — each "vector" is
# [len%128, first-byte%128, last-byte%128, 7] packed signed-byte and
# base64'd, deterministic per text. A text equal to "BOOM" answers an
# error envelope (the abort path).
#
# Spawn: ruby test/fixtures/embed/fake_worker.rb
# (fixtures/, deliberately: test/support/ is auto-required by
# test_helper, and this file RUNS a protocol loop at load.)

require "json"

DIM = 4

def encode(text)
  bytes = text.bytes
  values = [text.length % 128, (bytes.first || 0) % 128, (bytes.last || 0) % 128, 7]
  [values.pack("c*")].pack("m0")
end

$stdout.sync = true
puts JSON.generate({ "ready" => true, "worker" => "fake-e5", "version" => "0.0.1",
                     "model" => "multilingual-e5-base", "dim" => DIM, "encoding" => "i8" })

while (line = $stdin.gets)
  request = JSON.parse(line)
  if request["texts"].include?("BOOM")
    puts JSON.generate({ "id" => request["id"], "error" => "FakeError: boom requested" })
    next
  end
  puts JSON.generate({ "id" => request["id"],
                       "vectors" => request["texts"].map { |text| encode(text) } })
end
