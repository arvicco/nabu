# frozen_string_literal: true

# The suite's stand-in for script/stanza_lemma_worker.py (P84-1): speaks
# the exact worker protocol (ready line, then JSONL request/response) with
# a deterministic toy lemmatizer, so LemmaEnrich tests exercise the real
# Shell.duplex plumbing with no Python, no venv, no model — the
# enricher-tests-stub-model-calls rule at subprocess grain.
#
# Toy rules: each whitespace token lemmatizes to its downcased form with a
# few Latin-looking endings chopped ("fronte" -> "frons" it is not — the
# point is determinism, not Latin). A text equal to "BOOM" answers an
# error envelope (the abort path); upos is always "X".
#
# Spawn: ruby test/fixtures/lemma/fake_worker.rb [--die-after N]
# (fixtures/, deliberately: test/support/ is auto-required by test_helper,
# and this file RUNS a protocol loop at load.)

require "json"

def lemmatize(word)
  word.downcase.sub(/(ibus|arum|orum|ae|am|as|is|os|um|em|es)\z/, "a")
end

$stdout.sync = true
answered = 0
die_after = ARGV.include?("--die-after") ? Integer(ARGV[ARGV.index("--die-after") + 1]) : nil

puts JSON.generate({ "ready" => true, "worker" => "fake", "version" => "0.0.1",
                     "lang" => "la", "lemma_model" => "fake_toy" })

while (line = $stdin.gets)
  request = JSON.parse(line)
  if request["texts"].include?("BOOM")
    puts JSON.generate({ "id" => request["id"], "error" => "FakeError: boom requested" })
    next
  end
  results = request["texts"].map do |text|
    text.split.map { |word| [word, lemmatize(word), "X"] }
  end
  puts JSON.generate({ "id" => request["id"], "results" => results })
  answered += 1
  exit 0 if die_after && answered >= die_after
end
