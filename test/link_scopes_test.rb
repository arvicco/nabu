# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LinkScopes (P70-3b): batch-mined link scopes are config-durable —
# the batch CLIs record them, rebuild's links stage replays them, and
# db/links.sqlite3 becomes a pure function of canonical + config + catalog.
class LinkScopesTest < Minitest::Test
  def test_record_dedupes_by_producer_and_scope_and_load_roundtrips
    Dir.mktmpdir do |dir|
      path = File.join(dir, "link_scopes.yml")
      assert_empty Nabu::LinkScopes.load(path)
      Nabu::LinkScopes.record!(path, producer: "parallels", scope: "urn:x", params: { "lang" => "grc" })
      Nabu::LinkScopes.record!(path, producer: "cognates", scope: "nt", params: { "langs" => %w[got chu] })
      Nabu::LinkScopes.record!(path, producer: "parallels", scope: "urn:x", params: { "lang" => "lat" })
      scopes = Nabu::LinkScopes.load(path)
      assert_equal 2, scopes.size, "same producer+scope replaces — the latest params govern"
      assert_equal "lat", scopes.find { |s| s["producer"] == "parallels" }["params"]["lang"]
      assert_match(/derivability/, File.read(path))
    end
  end
end
