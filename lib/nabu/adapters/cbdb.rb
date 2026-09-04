# frozen_string_literal: true

require "json"
require "digest"

module Nabu
  module Adapters
    # CBDB — the China Biographical Database (Harvard/AS/Peking; Bol et
    # al.), registered as a FEATURE MODULE (P96-4): the prosopographical
    # instrument — ~658k persons of the 7th–19th centuries with names,
    # dates, offices, kinship and PLACE links — held as the acquired
    # SQLite artifact. v1 is ACQUISITION + verification only: no index
    # derives yet — the persons-layer scout (this phase's rider) ends in
    # the ruling that decides what a persons surface even is, informed
    # by this artifact's actual shape.
    #
    # == The self-pinning channel (P96-0 read, 2026-09-04)
    #
    # The project's cbdb_sqlite repo publishes latest.json — filename,
    # SHA-256, and the direct Hugging Face URL of the current release
    # (cbdb_20260829 at the read). fetch reads it, downloads the zip,
    # verifies the pin, and unpacks the sqlite — a moved or tampered
    # artifact refuses loudly; a re-fetch of an unchanged release is a
    # no-op by sha.
    #
    # == License (the drift the P96-0 read caught)
    #
    # Q63's 2026-09-02 note recorded the PRE-2018 license (BY-NC-SA).
    # The project's current statements (the JOHD 2022 paper and the
    # project handbook records) say **CC BY-NC-ND 4.0**, with a
    # mainland-China exclusive commercial license carved out to
    # ChineseAll. The primary download page answers 403 to
    # non-browsers, so the owner EYEBALLS the page's verbatim terms at
    # first sync. ND-honest posture: the artifact is held verbatim for
    # local research (ND restricts sharing adaptations, not making
    # them privately); class nc — and nothing here is served as text
    # anyway (a module mints no documents).
    class Cbdb < Nabu::Adapter
      LATEST_JSON_URL = "https://raw.githubusercontent.com/cbdb-project/cbdb_sqlite/master/latest.json"

      MANIFEST = Nabu::SourceManifest.new(
        id: "cbdb",
        name: "CBDB — China Biographical Database (prosopography instrument)",
        license: "CC BY-NC-ND 4.0 (per the project's JOHD 2022 paper; the pre-2018 grant was " \
                 "BY-NC-SA — owner eyeballs the download page's verbatim terms at first sync; " \
                 "mainland-China exclusive commercial license carved out to ChineseAll)",
        license_class: "nc",
        upstream_url: "https://github.com/cbdb-project/cbdb_sqlite",
        parser_family: "cbdb-sqlite"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "latest.json", zip_url: LATEST_JSON_URL, metadata_url: nil,
          state_subdir: "", state_file: STATE_FILE
        )]
      end

      STATE_FILE = ".cbdb-fetch.json"

      # A feature module mints no documents (the cigs/chgis shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: cbdb is a prosopography instrument, not a text " \
                          "source — parse is unreachable (the persons surface is a future ruling)"
      end

      # latest.json → sha-verified zip → the sqlite lands beside a state
      # file pinning release name + sha. An unchanged release is a no-op.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        release = latest_release
        if current?(workdir, release)
          return FetchReport.new(sha: release.fetch("sha256"), fetched_at: Time.now,
                                 notes: "already at #{release.fetch('sqlite_filename')}")
        end

        progress&.call("Downloading #{release.fetch('huggingface_url')}…\n")
        download_and_verify!(workdir, release)
        FetchReport.new(sha: release.fetch("sha256"), fetched_at: Time.now,
                        notes: "release #{release.fetch('sqlite_filename')} (sha verified)")
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "cbdb fetch failed into #{workdir}: #{e.message}"
      end

      private

      def latest_release
        response, = Nabu::RedirectFollow.get(LATEST_JSON_URL, http: Nabu::ZipFetch.default_http,
                                                              error: ZipFetch::Error, accept: [200])
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "cbdb: latest.json unparseable: #{e.message}"
      end

      def current?(workdir, release)
        state_path = File.join(workdir, STATE_FILE)
        return false unless File.file?(state_path)

        state = JSON.parse(File.read(state_path))
        state["sha256"] == release["sha256"] &&
          File.file?(File.join(workdir, release.fetch("sqlite_filename")))
      rescue JSON::ParserError
        false
      end

      def download_and_verify!(workdir, release)
        response, = Nabu::RedirectFollow.get(release.fetch("huggingface_url"),
                                             http: Nabu::ZipFetch.default_http,
                                             error: ZipFetch::Error, accept: [200])
        body = response.body.to_s.b
        zip_path = File.join(workdir, "cbdb.zip")
        File.binwrite(zip_path, body)
        unpack_and_pin!(workdir, release, zip_path)
      ensure
        FileUtils.rm_f(File.join(workdir, "cbdb.zip"))
      end

      def unpack_and_pin!(workdir, release, zip_path)
        Shell.run("unzip", "-o", "-q", zip_path, "-d", workdir)
        sqlite = File.join(workdir, release.fetch("sqlite_filename"))
        raise Nabu::FetchError, "cbdb: zip held no #{release.fetch('sqlite_filename')}" unless File.file?(sqlite)

        actual = Digest::SHA256.file(sqlite).hexdigest
        unless actual == release.fetch("sha256")
          File.delete(sqlite)
          raise Nabu::FetchError, "cbdb: sqlite sha mismatch (got #{actual}, latest.json pins " \
                                  "#{release.fetch('sha256')}) — refused"
        end
        File.write(File.join(workdir, STATE_FILE),
                   JSON.pretty_generate(release.merge("verified_at" => Time.now.utc.iso8601)))
      end
    end
  end
end
