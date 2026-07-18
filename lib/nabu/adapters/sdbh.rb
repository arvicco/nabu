# frozen_string_literal: true

require_relative "sdbh_xml_parser"

module Nabu
  module Adapters
    # SDBH (P30-2): the *UBS Dictionary of Biblical Hebrew* — the CC BY-SA
    # open-license extract of the Semantic Dictionary of Biblical Hebrew
    # (SDBH, © United Bible Societies 2000–2023; ed. Reinier de Blois) —
    # the SECOND Hebrew dictionary shelf, deliberately unmerged with any
    # sibling Hebrew lexicon (the MW-beside-kaikki precedent: two shelves,
    # two upstream identities, define shows both). content_kind
    # :dictionary, slug sdbh, dictionary language hbo with per-entry arc
    # tagging (372 all-A-code entries measured on the full file; the
    # @HasAramaic attribute marks 680 but includes mixed H+A lemmas).
    #
    # == Upstream (censused 2026-07-18, commit 3a6edd82)
    #
    # github.com/ubsicap/ubs-open-license — the repo layout was INSPECTED,
    # not guessed: SDBH lives at dictionaries/hebrew/XML/
    # UBSHebrewDic-v0.9.2-en.XML (37,001,017 bytes; sha256 f80096ea…),
    # with sibling es/fr/pt/zh-hans/zh-hant translations, JSON mirrors,
    # and a small UBSHebrewDicLexicalDomains-v0.9.2-en.XML (the domain
    # hierarchy lookup — journaled, not fetched: every <LEXDomain> in the
    # entries file carries its own label + hierarchy code). Only the
    # English entries XML is fetched. v0.9.2 census: 7,932 entries /
    # 16,220 non-empty definitions / 23,879 non-empty glosses / 260,813
    # LEXReferences / 9,079 Strong codes in the H/A number space (the
    # OSHB/OSHM augmented-Strong join space).
    #
    # == License (dictionaries/hebrew/README.md, quoted verbatim)
    #
    # "This work is licensed under a Creative Commons Attribution-ShareAlike
    # 4.0 International License." … "(UBS Dictionary of Biblical Hebrew ©
    # United Bible Societies, 2023. Adapted from Semantic Dictionary of
    # Biblical Hebrew © 2000-2023 United Bible Societies.)"
    #
    # → CC BY-SA 4.0, license_class "attribution" (share-alike rides any
    # future redistribution, noted in 02-sources; local research + index
    # is squarely inside the grant). The grant lives in the repo's README
    # beside the file, not in a probe-shaped JSON endpoint → metadata_url
    # nil, honestly unchecked between refetches (the MW/ASPR stance).
    #
    # == fetch / parse
    #
    # Single-file HTTP via Nabu::FileFetch over the raw.githubusercontent
    # URL (conditional GET on Last-Modified, sha256 pin, attic +
    # mass-deletion guard — a future v1.0 FILENAME migration attics the
    # old version automatically). Parse streams with Nokogiri::XML::Reader
    # (37 MB — the no-DOM-over-5MB rule). The discover ref id is
    # VERSION-FREE ("sdbh:UBSHebrewDic-en.XML") so entry urns survive an
    # upstream version bump; when two versions coexist transiently the
    # lexically-newest filename wins.
    #
    # SDBH is ~90% complete upstream ("The remaining 10% will be added
    # once they become available" — hebrew README): the honest coverage
    # numbers live in docs/02-sources.md row 83.
    class Sdbh < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "sdbh",
        name: "UBS Dictionary of Biblical Hebrew (Semantic Dictionary of Biblical Hebrew)",
        license: "CC BY-SA 4.0 (\"This work is licensed under a Creative Commons Attribution-ShareAlike " \
                 "4.0 International License.\" — dictionaries/hebrew/README.md; \"UBS Dictionary of " \
                 "Biblical Hebrew © United Bible Societies, 2023. Adapted from Semantic Dictionary of " \
                 "Biblical Hebrew © 2000-2023 United Bible Societies.\")",
        license_class: "attribution",
        upstream_url: "https://raw.githubusercontent.com/ubsicap/ubs-open-license/main/" \
                      "dictionaries/hebrew/XML/UBSHebrewDic-v0.9.2-en.XML",
        parser_family: "sdbh-xml"
      )

      XML_FILENAME = "UBSHebrewDic-v0.9.2-en.XML"
      XML_GLOB = "UBSHebrewDic-v*-en.XML"
      DICTIONARY_SLUG = "sdbh"
      LANGUAGE = "hbo"
      TITLE = "UBS Dictionary of Biblical Hebrew (SDBH)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs the raw file itself: reachability + Last-Modified
      # drift vs the .file-fetch.json pin. metadata_url nil — see the
      # license note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: XML_FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the one dictionary file, under ONE version-free
      # id: entry urns must survive a v0.9.2 → v1.0 upstream rename. When a
      # transient overlap leaves two versions on disk, the lexically-newest
      # filename wins (FileFetch attics the stale one on the next sync).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = Dir.glob(File.join(workdir, "**", XML_GLOB)).max or return
        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:UBSHebrewDic-en.XML",
          path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG }
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        SdbhXmlParser.new.entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "sdbh: #{document_ref.id}: #{e.message}"
      end

      # Download the raw XML via FileFetch (conditional GET, sha pin, attic
      # + guard contract). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: XML_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "sdbh fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
