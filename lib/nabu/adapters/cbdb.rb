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
    # == License (settled at first sync, 2026-09-11)
    #
    # **CC BY-NC-SA 4.0** — the owner read the project site's verbatim
    # terms at first sync (the page 403s non-browser clients), and the
    # Hugging Face dataset card (cbdb/cbdb-sqlite) declares the same.
    # The JOHD 2022 paper's BY-NC-ND wording is the outlier and does
    # not govern the distribution channel we fetch. A mainland-China
    # exclusive commercial license is carved out to ChineseAll. Class
    # nc; the artifact is held verbatim for local research — a module
    # mints no documents.
    class Cbdb < Nabu::Adapter
      LATEST_JSON_URL = "https://raw.githubusercontent.com/cbdb-project/cbdb_sqlite/master/latest.json"

      MANIFEST = Nabu::SourceManifest.new(
        id: "cbdb",
        name: "CBDB — China Biographical Database (prosopography instrument)",
        license: "CC BY-NC-SA 4.0 (project site verbatim, owner-read at first sync 2026-09-11; " \
                 "the Hugging Face dataset card concurs; the JOHD 2022 paper's BY-NC-ND is the " \
                 "outlier; mainland-China exclusive commercial license carved out to ChineseAll)",
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

      # P97-2 (№R-62 option b): the acquisition-only module grows its
      # first derived surface — the "cbdb" person-index slice.
      def self.person_index_producer? = true

      def self.person_index_producer(catalog:)
        Nabu::CbdbPersons::Producer.new(catalog: catalog)
      end

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
