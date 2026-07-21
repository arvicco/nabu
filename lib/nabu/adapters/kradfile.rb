# frozen_string_literal: true

require "zlib"

require_relative "kradfile_parser"

module Nabu
  module Adapters
    # The KRADFILE adapter (P37-4, survey-ratified): the EDRDG kanji→component
    # decomposition index — the exact dataset behind Jisho's multi-radical
    # component search — feeding `nabu char`'s component-index row and the
    # `search --char-component` flat-containment filter over its JIS X 0208
    # span (6,355 kanji). content_kind :dictionary, slug kradfile,
    # language jpn. A sibling of the `edrdg` source (same org, same licence
    # document) kept as its own row so the base-pair licence stays uniform;
    # BabelStone IDS supplies the pan-CJK transitive-containment span this
    # JIS-kanji index cannot reach.
    #
    # == License (edrdg.org/edrdg/licence.html §2, verbatim) — `attribution`
    #
    # The SAME EDRDG document our `edrdg` (KANJIDIC2 + JMdict) row already
    # quotes enumerates RADKFILE/KRADFILE in its scope: "RADKFILE/KRADFILE —
    # files relating to the decomposition of the 6,355 kanji in JIS X 0208
    # into their visible components", under "The dictionary files are made
    # available under a Creative Commons Attribution-ShareAlike Licence
    # (V4.0)." → license_class "attribution", zero new licence surface.
    # © Michael Raine, James Breen and the EDRDG. (The KRADFILE2/RADKFILE2
    # JIS X 0212 extension — © Jim Rose, same EDRDG licence — is OUT of v1;
    # the base pair is the cleanest, licence-uniform position.)
    #
    # == fetch / sync policy
    #
    # Single-file HTTP via Nabu::FileFetch on kradfile.gz (conditional GET,
    # sha pin, attic + guard). Historically EUC-JP; parse gunzips (canonical
    # keeps the .gz verbatim) and transcodes EUC-JP→UTF-8, NFC at the
    # boundary. Low cadence (revisions Feb 2008 / Jul 2017 / Aug 2021 —
    # effectively stable) → sync_policy manual, enabled: false until the
    # owner-fired first sync. The :http_zip probe HEADs the .gz;
    # metadata_url nil — the licence is a static page.
    class Kradfile < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "kradfile",
        name: "KRADFILE — EDRDG kanji→component decomposition index (Raine, Breen & EDRDG)",
        license: "CC BY-SA 4.0 (verbatim, edrdg.org/edrdg/licence.html — the same EDRDG document " \
                 "cited by the edrdg row: \"The dictionary files are made available under a Creative " \
                 "Commons Attribution-ShareAlike Licence (V4.0).\", scope §2 naming RADKFILE/KRADFILE; " \
                 "© Michael Raine, James Breen and the EDRDG)",
        license_class: "attribution",
        upstream_url: "http://ftp.edrdg.org/pub/Nihongo/kradfile.gz",
        parser_family: "radkfile"
      )

      GZ = "kradfile.gz"
      PLAIN = "kradfile"
      DICTIONARY_SLUG = "kradfile"
      LANGUAGE = "jpn"
      TITLE = "KRADFILE — kanji→component decomposition index (EDRDG)"
      # Historical EDRDG distribution encoding of the KRADFILE body.
      SOURCE_ENCODING = "EUC-JP"

      def self.manifest = MANIFEST

      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: GZ, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef under a stable id regardless of shape: the plain
      # `kradfile` (fixtures / hand-unpacked) wins over the `kradfile.gz`
      # (the real post-fetch canonical). A workdir with neither yields
      # nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path, gzip = kradfile_path(workdir)
        return if path.nil?

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{PLAIN}",
          path: File.expand_path(path),
          metadata: gzip ? { "dictionary" => DICTIONARY_SLUG, "gzip" => "true" } : { "dictionary" => DICTIONARY_SLUG }
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        each_line(document_ref) do |lines|
          KradfileParser.new.entries(lines, language: LANGUAGE).each { |entry| document << entry }
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "kradfile: #{document_ref.id}: #{e.message}"
      rescue Zlib::Error => e
        raise Nabu::ParseError, "kradfile: #{document_ref.id}: corrupt gzip: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: GZ,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "kradfile fetch failed into #{workdir}: #{e.message}"
      end

      private

      # [path, gzip?] — plain first, then gz; nil when neither exists.
      def kradfile_path(workdir)
        plain = Dir.glob(File.join(workdir, "**", PLAIN)).reject { |p| p.end_with?(".gz") }.min
        return [plain, false] if plain

        gz = Dir.glob(File.join(workdir, "**", GZ)).min
        gz ? [gz, true] : [nil, false]
      end

      # Yields an array of UTF-8 lines (EUC-JP decoded, gunzipped when the
      # canonical .gz shape). One array so the parser can be re-run.
      def each_line(document_ref)
        if document_ref.metadata["gzip"]
          Zlib::GzipReader.open(document_ref.path) do |gz|
            yield gz.read.force_encoding(SOURCE_ENCODING).encode(Encoding::UTF_8).lines
          end
        else
          yield File.read(document_ref.path, encoding: "#{SOURCE_ENCODING}:UTF-8").lines
        end
      end
    end
  end
end
