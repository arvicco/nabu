# frozen_string_literal: true

require "digest"

require_relative "ptg_tei_parser"

module Nabu
  module Adapters
    # The DILA Pentaglot adapter: the Wuyi hebi jiyao 五譯合璧集要, a
    # Qing-era five-language Buddhist terminology list, as reprinted with
    # indices by Raghu Vira ("Pentaglot Dictionary of Buddhist Terms",
    # Delhi 1961), in the DILA / Dharma Drum TEI P5 digital edition — the
    # mvp sibling on the same glossaries.dila.edu.tw delivery. 1,071 terms
    # in Sanskrit (IAST), Manchu (Möllendorff romanization), Mongolian
    # (romanized Classical Mongolian) and Chinese; the Tibetan column is
    # present but empty throughout (upstream: "We have not digitized the
    # Tibetan terms as yet").
    #
    # == Four shelves, one source
    #
    # A mirror dictionary has no headword language, so every digitized
    # column heads its own dictionary shelf (the hdic / oracc-glossary
    # one-source-many-dictionaries shape): ptg-san, ptg-mnc, ptg-cmg,
    # ptg-lzh, each entry carrying all columns as labeled body lanes. The
    # split is what makes each column a lookup direction — Query::Define
    # folds a query with the DICTIONARY's language, so a Manchu or
    # Mongolian headword is only reachable from a shelf in that language.
    # Language mapping: san-Latn → san; mnc-Latn → mnc; mon-Latn → cmg
    # (the column is the classical written language, not modern Khalkha —
    # the nabu-lects cmg node names this dictionary as its consumer);
    # zho-Hant → lzh (Buddhist literary Chinese, the cbeta precedent).
    # Entry ids are upstream's page.item xml:ids (urn:nabu:dict:ptg-mnc:
    # p005.2 = fucihi, "Buddha").
    #
    # == Upstream (verified 2026-11-04)
    #
    # https://glossaries.dila.edu.tw/glossaries/PTG — XML-source download
    # pentaglot.dila.tei.p5.xml.zip [42.09 KiB, 2017-03-20; 43,101 B,
    # Last-Modified 2017-03-20 06:37:38 GMT], one member (465,625 B,
    # UTF-8 with BOM) plus __MACOSX junk. The page's other grains (HTML
    # zip, EPUB, Stardict, Babylon GLS, PDF) are renderings of the same
    # file and are not fetched. Frozen since 2017 → a hard sha256 pin;
    # a drift is an owner re-pin decision.
    #
    # Reconciliation vs upstream's advertised "1071 terms": the member
    # carries 1,071 <entry> elements = 1,070 real entries + 1 placeholder
    # (p341A.1, an XML comment only — Bawden's Manchu index cites a page
    # DILA could not trace), skipped by rule. Shelf sizes: san 1,070,
    # mnc 1,068, cmg 1,069, lzh 1,069 (4,276 rows) — the 2 / 1 / 1 empty
    # columns upstream left blank.
    #
    # == License (the honest-license doctrine)
    #
    # The glossary page, verbatim: "We believe this text is in the public
    # domain." and "This digital version is licensed by DILA under a
    # Creative Commons Attribution-Share Alike 3.0 Taiwan License." →
    # license_class "attribution" (the BY-SA class, hdic precedent). The
    # TEI header inside the 2011 member still names the predecessor terms
    # ("licensed by DDBC under a Creative Commons Attribution-Share Alike
    # 2.5 Taiwan License"); the live page's 3.0 TW statement governs.
    class Ptg < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "ptg",
        name: "Pentaglot Dictionary of Buddhist Terms — Sanskrit–Manchu–Mongolian–Chinese (DILA TEI edition)",
        license: "CC BY-SA 3.0 TW — verbatim (glossaries.dila.edu.tw/glossaries/PTG): " \
                 "\"We believe this text is in the public domain.\" \"This digital version is licensed " \
                 "by DILA under a Creative Commons Attribution-Share Alike 3.0 Taiwan License.\"",
        license_class: "attribution",
        upstream_url: "https://glossaries.dila.edu.tw/data/pentaglot.dila.tei.p5.xml.zip",
        parser_family: "ptg-tei",
        credit: "Glossaries Team, Dharma Drum Buddhist College (DILA), glossaries.dila.edu.tw — " \
                "data input Baolian 鄭寶蓮 (Sanskrit, Manchu, Chinese) and Sarnai Narayan (Mongolian), " \
                "XML Simon Wiles, editor Marcus Bingenheimer"
      )

      ZIP_FILENAME = "pentaglot.dila.tei.p5.xml.zip"
      XML_FILENAME = "pentaglot.dila.tei.p5.xml"

      # Shelf slug → [house language, title], the parser's column order.
      SHELVES = {
        "ptg-san" => ["san", "Pentaglot (DILA) — Sanskrit"],
        "ptg-mnc" => ["mnc", "Pentaglot (DILA) — Manchu"],
        "ptg-cmg" => ["cmg", "Pentaglot (DILA) — Classical Mongolian"],
        "ptg-lzh" => ["lzh", "Pentaglot (DILA) — Chinese"]
      }.freeze

      # sha256 of the upstream zip, pinned from the 2026-11-04 download
      # (upstream dated 2017-03-20 — effectively frozen).
      ZIP_SHA256 = "ed0519c108873a4d5f2ba500218fdbf5d771519a913feea3ee84398a88550393"

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      # The probe HEADs the zip itself; the license statement lives on the
      # glossary HTML page, re-read at any real refetch.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: ZIP_FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +zip_sha256+ exists for the WebMock'd fetch tests — real syncs keep
      # the frozen pin.
      def initialize(zip_sha256: ZIP_SHA256)
        super()
        @zip_sha256 = zip_sha256
      end

      # One DocumentRef per shelf over the one dictionary file: a plain XML
      # (fixtures) wins over the zip (the real post-fetch canonical). A
      # workdir with neither yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path, member = source_file(workdir)
        return unless path

        SHELVES.each_key { |slug| yield document_ref(slug, path, member: member) }
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        language, title = SHELVES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: language, title: title, canonical_path: document_ref.path
        )
        PtgTeiParser.new.entries(xml_source(document_ref), language: language, path: document_ref.path)
                    .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "ptg: #{document_ref.id}: #{e.message}"
      end

      # Download the zip via FileFetch with the phases run separately so the
      # sha pin verifies BEFORE the tree mutates (the mvp choreography).
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(
          url: manifest.upstream_url, dir: workdir, filename: ZIP_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ptg fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.sha == @zip_sha256

        raise Nabu::FetchError,
              "ptg: #{ZIP_FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned #{@zip_sha256} " \
              "(upstream dated 2017-03-20); review upstream and re-pin (owner decision)"
      end

      def source_file(workdir)
        plain = Dir.glob(File.join(workdir, "**", XML_FILENAME)).min
        return [plain, nil] if plain

        zip = Dir.glob(File.join(workdir, "**", ZIP_FILENAME)).min
        zip ? [zip, XML_FILENAME] : nil
      end

      def document_ref(slug, path, member:)
        metadata = { "dictionary" => slug }
        metadata["member"] = member if member
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{slug}:#{XML_FILENAME}",
          path: File.expand_path(path), metadata: metadata
        )
      end

      # The TEI source: straight off the plain file, or streamed out of the
      # zip member (unzip -p via Nabu::Shell; the __MACOSX junk member is
      # never named).
      def xml_source(document_ref)
        member = document_ref.metadata["member"]
        return SourceRead.utf8_file(document_ref.path, label: "ptg") if member.nil?

        SourceRead.utf8(Nabu::Shell.run("unzip", "-p", document_ref.path, member), label: "ptg: zip:#{member}")
      rescue Nabu::Shell::Error => e
        raise Nabu::ParseError, "ptg: cannot read #{member} from #{document_ref.path}: #{e.message}"
      end
    end
  end
end
