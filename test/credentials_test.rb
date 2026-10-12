# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "pp"

# The credentials seam (Nabu::Credentials): local/config/credentials.yml is
# the ONE home of stored upstream credentials (a gated member area's Basic-
# auth user + password, or a token). Written only through the `nabu creds`
# gateway, always mode 600; read by the fetch layer through
# Credentials.for(name). No path may print, log or inspect a secret.
class CredentialsTest < Minitest::Test
  SECRET = "s3cr3t-rotating-Pa55"

  def setup
    @root = Dir.mktmpdir("nabu-creds")
    @path = File.join(@root, "local", "config", "credentials.yml")
    @store = Nabu::Credentials.new(path: @path)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_an_absent_file_holds_nothing
    assert_nil @store["titus"]
    assert_empty @store.list
    refute_path_exists @path, "reading never creates the file"
  end

  def test_set_round_trips_and_writes_an_owner_only_file
    status = @store.set!("titus", user: "member", password: SECRET, now: Time.utc(2026, 10, 12, 9))
    assert_equal :stored, status
    entry = Nabu::Credentials.new(path: @path)["titus"]
    assert_equal "titus", entry.name
    assert_equal "member", entry.user
    assert_equal SECRET, entry.password
    assert_nil entry.token
    assert_equal Time.utc(2026, 10, 12, 9), entry.updated_at
    assert_equal 0o600, File.stat(@path).mode & 0o777, "the credentials file is owner-only"
  end

  def test_a_rewrite_keeps_the_file_600_even_if_it_was_widened
    @store.set!("titus", user: "member", password: SECRET)
    File.chmod(0o644, @path)
    @store.set!("titus", user: "member", password: "rotated-#{SECRET}")
    assert_equal 0o600, File.stat(@path).mode & 0o777
  end

  def test_re_set_with_the_same_values_is_idempotent
    first = Time.utc(2026, 10, 1)
    @store.set!("titus", user: "member", password: SECRET, now: first)
    bytes = File.binread(@path)
    status = @store.set!("titus", user: "member", password: SECRET, now: Time.utc(2026, 10, 12))
    assert_equal :unchanged, status
    assert_equal bytes, File.binread(@path), "an unchanged re-set rewrites nothing"
    assert_equal first, @store["titus"].updated_at, "the age stays the age of the secret"
  end

  def test_a_rotated_password_updates_the_entry_and_its_age
    @store.set!("titus", user: "member", password: SECRET, now: Time.utc(2026, 10, 1))
    status = @store.set!("titus", user: "member", password: "new-#{SECRET}", now: Time.utc(2026, 10, 12))
    assert_equal :updated, status
    assert_equal "new-#{SECRET}", @store["titus"].password
    assert_equal Time.utc(2026, 10, 12), @store["titus"].updated_at
  end

  def test_entries_coexist_and_list_names_and_ages_only
    @store.set!("titus", user: "member", password: SECRET, now: Time.utc(2026, 10, 1))
    @store.set!("other", user: nil, token: "tok-#{SECRET}", now: Time.utc(2026, 10, 2))
    listing = @store.list
    assert_equal %w[other titus], listing.map(&:first)
    assert_equal [Time.utc(2026, 10, 2), Time.utc(2026, 10, 1)], listing.map(&:last)
    refute_includes listing.inspect, SECRET, "a listing carries no secret"
    assert_equal "tok-#{SECRET}", @store["other"].token
  end

  def test_set_rejects_an_empty_secret_and_a_bad_name
    assert_raises(Nabu::ValidationError) { @store.set!("titus", user: "member", password: "") }
    assert_raises(Nabu::ValidationError) { @store.set!("titus", user: "member") }
    assert_raises(Nabu::ValidationError) { @store.set!("Bad Name", user: "u", password: "p") }
    refute_path_exists @path
  end

  def test_the_entry_never_reveals_its_secret_when_printed
    @store.set!("titus", user: "member", password: SECRET)
    entry = @store["titus"]
    shown_forms = [entry.inspect, entry.to_s, entry.pretty_inspect, "entry: #{entry}", [entry].inspect,
                   { e: entry }.inspect]
    shown_forms.each do |shown|
      refute_includes shown, SECRET, "a printed entry must redact the password"
      assert_includes shown, "[REDACTED]"
    end
    token = Nabu::Credentials::Entry.new(name: "x", user: nil, password: nil, token: SECRET, updated_at: nil)
    refute_includes token.inspect, SECRET
  end

  def test_the_store_never_reveals_secrets_when_inspected
    @store.set!("titus", user: "member", password: SECRET)
    refute_includes @store.inspect, SECRET
  end

  def test_basic_auth_header_is_rfc7617
    entry = Nabu::Credentials::Entry.new(name: "titus", user: "Aladdin", password: "open sesame",
                                         token: nil, updated_at: nil)
    assert_equal "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ==", entry.basic_auth_header
  end

  def test_for_reads_the_default_home
    @store.set!("titus", user: "member", password: SECRET)
    assert_equal "member", Nabu::Credentials.for("titus", path: @path).user
    assert_nil Nabu::Credentials.for("nope", path: @path)
  end

  def test_config_names_the_one_home_under_local_config
    config = Nabu::Config.new(canonical_dir: File.join(@root, "canonical"), db_dir: File.join(@root, "db"),
                              sources_path: File.join(@root, "config", "sources.yml"),
                              config_path: File.join(@root, "config", "nabu.yml"))
    assert_equal File.join(@root, "local", "config", "credentials.yml"), config.credentials_path
  end

  def test_the_refusal_and_rejection_messages_are_verbatim
    assert_equal "credentials required: run bin/nabu creds set titus", Nabu::Credentials.required_message("titus")
    assert_equal "titus credentials rejected (rotated?) — run bin/nabu creds set titus",
                 Nabu::Credentials.rejected_message("titus")
    assert_operator Nabu::Credentials::Missing, :<, Nabu::FetchError
    assert_operator Nabu::Credentials::Rejected, :<, Nabu::FetchError
  end
end
