# frozen_string_literal: true

require_relative "korp_jsonl_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # The VKS adapter: Vanhan kirjasuomen korpus, the Corpus of Old Literary
    # Finnish (Institute for the Languages of Finland, Kotus; distributed by
    # the Language Bank of Finland, Kielipankki — Korp version
    # urn:nbn:fi:lb-201407166, metadata urn:nbn:fi:lb-201407165). The
    # written Finnish of 1543–1810 whole: every work of Mikael Agricola
    # (1543–1552), the first complete Finnish Bible (1642), Hemminki of
    # Masku's hymnal (1605) and the 1701 hymnal, the Swedish realm's laws
    # and decrees in Finnish (1555–1810), sermons, almanacs (1705–1809),
    # Lizelius' newspaper (1775–76), Ganander's and Frosterus' and
    # Björkqvist's prints, and the miscellany shelf — 4,133,202 tokens /
    # 167,400 Korp sentences in 134 text files across 12 subcorpora.
    #
    # == Upstream and grains (the acquisition route)
    #
    # Kielipankki publishes NO bulk download of VKS; the anonymous Korp
    # JSON API (www.kielipankki.fi/korp/api8 — korp.csc.fi redirects there)
    # answers PUB corpora without login. Nabu::KorpFetch harvests the 12
    # subcorpora VKS_AGRICOLA … VKS_VIRRET sentence by sentence (cqp
    # "<sentence> []", context 1 sentence, 1,000 sentences a request) and
    # lands texts/<CORPUS>/<text-file>.jsonl — one line per sentence, the
    # kwic row's structural attributes verbatim and its tokens repacked
    # [word, word_completed, word_tilde]. Grains upstream serves:
    #   corpus (12 VKS_* subcorpora)  — the harvest unit (a subdir)
    #   text file (text_filename, 134) — THE DOCUMENT
    #   text element (a dated <text> inside a file — the decree and sermon
    #       collections hold one per year) — rides as the passage "date"
    #   sentence_code (the corpus's line/verse/paragraph key) — THE PASSAGE
    #       (KorpJsonlParser: one passage per run of a code)
    #   Korp sentence — a sub-passage segmentation, folded into its code
    #   token (word / word_completed / word_tilde) — word is the text, the
    #       completed abbreviations ride as "expansions"
    # Not served by this route: lemma or morphology (the Korp VKS carries
    # none — the separate Agricola morpho-database is its own resource)
    # and the inline foreign/error spans (structural attributes WITHOUT
    # values, so the kwic rows cannot carry them — declared coarse: a
    # Swedish or Latin passage inside a Finnish work reads fi).
    #
    # == Reconciliation (pre-flight census, 2026-10-21)
    #
    # corpus_info: 12 corpora, 4,133,202 tokens, 167,400 sentences;
    # struct_values text_filename: 134 files (agricola 12 · almanakat 1 ·
    # biblia 10 · bjorkqvist 2 · frosterus 1 · ganander 10 · lait 15 ·
    # lizelius 3 · lpetri 3 · saarnat 2 · varia 71 · virret 4). The
    # harvest refuses a page whose hit total differs from corpus_info's
    # sentence count, so accepted documents = the files served. First
    # real harvest pending — the gate re-states these counts.
    #
    # == Identity
    #
    #   document urn  urn:nabu:vks:<corpus>.<file stem>   (lowercased:
    #                 urn:nabu:vks:frosterus.jafro1791)
    #   passage urn   <document urn>:<sentence_code, ":" read ".">
    #                 (…:biblia.ut1_ev:Jh-19.38-623c)
    #
    # == License
    #
    # EUPL v1.2. Kielipankki's Korp configuration for the VKS folder,
    # verbatim: licence name "EUPL v. 1.2", description "Euroopan unionin
    # yleinen lisenssi v. 1.2 (EUPL)" (the European Union Public Licence
    # v1.2), licence page urn:nbn:fi:lb-2024082106; Kielipankki's PUB
    # category (openly available). The ruling (2026-10-21): license_class
    # attribution WITH the share-alike flag — EUPL is a copyleft licence
    # (Art. 5: derivative works distributed under the EUPL or a listed
    # compatible licence) carrying attribution and notice duties; the
    # share-alike rider is recorded in docs/02-sources.md. The licence
    # page itself was unreachable at adapter time (kielipankki.fi down for
    # maintenance 2026-10-21; urn.fi behind a browser challenge) — re-read
    # it verbatim at the first harvest.
    #
    # == Axes
    #
    # date — every text element's text_datefrom/text_dateto (YYYYMMDD) →
    # the document envelope (min/max over the file) on the :structured
    # lane; a file holding several dated elements also dates each passage
    # ("date" annotation). author — the title's "Name: Title (year)"
    # head where the title has one ("Mikael Agricola: Abckiria (1543)"),
    # text_author verbatim where the corpus gives it. lect — fi throughout;
    # the Old Literary Finnish stage is a registry candidate
    # (postures.yml). places — VKS carries no place field — unplaced.
    # The facsimile edition each text was keyed from rides as "facsimile".
    #
    # == fetch / sync policy
    #
    # The Korp harvest (Nabu::KorpFetch; a measured ~5 minutes for the
    # whole corpus, progress per page). VKS is a closed historical corpus
    # last updated upstream 2016/2019 → sync_policy manual.
    class Vks < Nabu::Adapter
      BASE_URL = "https://www.kielipankki.fi/korp/api8"
      CORPORA = %w[VKS_AGRICOLA VKS_ALMANAKAT VKS_BIBLIA VKS_BJORKQVIST VKS_FROSTERUS VKS_GANANDER
                   VKS_LAIT VKS_LIZELIUS VKS_LPETRI VKS_SAARNAT VKS_VARIA VKS_VIRRET].freeze
      ATTRS = %w[word word_completed word_tilde].freeze
      STRUCTS = %w[text_filename text_title text_datefrom text_dateto text_year text_author
                   text_title_facsimile supplement_cRef div_n span_page sentence_id sentence_type
                   sentence_code sentence_cRef].freeze
      URN_PREFIX = "urn:nabu:vks:"
      LANGUAGE = "fi"
      # "Name: Title (year)" — a comma-free head is an author, never "Biblia, Se on: …".
      TITLE_HEAD = /\A(?<author>[^:,]{2,60}):\s+(?<title>.+)\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "vks",
        name: "VKS — Vanhan kirjasuomen korpus, the Corpus of Old Literary Finnish (Kotus, via Kielipankki Korp)",
        license: "EUPL v1.2 (Kielipankki's Korp configuration for VKS: licence \"EUPL v. 1.2\" — " \
                 "\"Euroopan unionin yleinen lisenssi v. 1.2 (EUPL)\", licence page " \
                 "urn:nbn:fi:lb-2024082106; Kielipankki category PUB). Copyleft: share-alike rider. " \
                 "Credit Vanhan kirjasuomen korpus, Kotimaisten kielten keskus (Institute for the Languages " \
                 "of Finland), Kielipankki, urn:nbn:fi:lb-201407166",
        license_class: "attribution",
        upstream_url: "https://urn.fi/urn:nbn:fi:lb-201407166",
        parser_family: "korp-jsonl"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Korp corpus_info (VKS)", zip_url: "#{BASE_URL}/corpus_info?corpus=#{CORPORA.join(',')}",
          metadata_url: nil, state_subdir: "", liveness_only: true
        )]
      end

      # One ref per landed texts/<CORPUS>/<stem>.jsonl, sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        jsonl_paths(workdir).map { |path| ref(path) }.sort_by(&:id).each(&block)
      end

      # A landed corpus directory outside the configured scope is
      # unrecognized (the scope and the tree disagree).
      def discovery_skips(workdir)
        root = File.join(workdir, KorpFetch::TEXTS_DIR)
        dirs = Dir.exist?(root) ? Dir.children(root).select { |d| File.directory?(File.join(root, d)) } : []
        stray = (dirs - CORPORA).sort
        Nabu::Adapter::DiscoverySkips.new(unrecognized: stray.size,
                                          notes: stray.map { |dir| "corpus outside the VKS scope: #{dir}" })
      end

      def parse(document_ref)
        text = SourceRead.utf8_file(document_ref.path, label: "vks")
        units, rows = parser.parse(text, label: document_ref.path)
        meta = document_ref.metadata.merge(text_metadata(rows))
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: meta["title"] || meta["vks_file"], metadata: meta.except("title"))
        units.each_with_index do |unit, sequence|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{unit.citation}", language: LANGUAGE,
                                        text: unit.text, annotations: unit.annotations, sequence: sequence)
        end
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::KorpFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          attrs: ATTRS, structs: STRUCTS, text_key: "text_filename", progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }, **fetch_options
        )
        notes = ["harvested #{result.sentences} sentences / #{result.texts} texts from #{result.corpora.size} corpora",
                 attic_notes(result.atticked)].compact.join("; ")
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue KorpFetch::Error => e
        raise Nabu::FetchError, "vks fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The harvest scope and pacing — a seam tests narrow (two corpora,
      # tiny pages, no politeness pause).
      def fetch_options = { corpora: CORPORA }

      def parser
        @parser ||= KorpJsonlParser.new
      end

      def jsonl_paths(workdir)
        Dir.glob(File.join(workdir, KorpFetch::TEXTS_DIR, "*", "*.jsonl"))
      end

      def ref(path)
        corpus = File.basename(File.dirname(path))
        stem = File.basename(path, ".jsonl")
        id = "#{URN_PREFIX}#{corpus.delete_prefix('VKS_').downcase}.#{stem.downcase}"
        Nabu::DocumentRef.new(source_id: MANIFEST.id, id: id, path: File.expand_path(path),
                              metadata: { "language" => LANGUAGE, "korp_corpus" => corpus })
      end

      # Text-level metadata from the parsed rows: title, author, the
      # envelope over every text element's dates, the facsimile edition.
      def text_metadata(rows)
        structs = rows.map { |row| row["structs"] }
        first = structs.first
        meta = { "vks_file" => first["text_filename"] }
        title = Normalize.nfc(first["text_title"].to_s.strip)
        unless title.empty?
          meta["title"] = title
          head = TITLE_HEAD.match(title)
          meta["author"] = Normalize.nfc(head[:author].strip) if head
        end
        authors = structs.map { |s| s["text_author"].to_s.strip }.reject(&:empty?).uniq
        meta["text_authors"] = authors.map { |a| Normalize.nfc(a) } unless authors.empty?
        facsimile = first["text_title_facsimile"].to_s.strip
        meta["facsimile"] = Normalize.nfc(facsimile) unless facsimile.empty?
        date = envelope(structs)
        meta["date"] = date if date
        meta
      end

      def envelope(structs)
        froms = structs.map { |s| s["text_datefrom"].to_s[0, 4] }.grep(/\A\d{4}\z/).map { |y| Integer(y, 10) }
        tos = structs.map { |s| s["text_dateto"].to_s[0, 4] }.grep(/\A\d{4}\z/).map { |y| Integer(y, 10) }
        return nil if froms.empty? || tos.empty?

        years = structs.map { |s| [s["text_datefrom"], s["text_dateto"]] }.uniq.size
        { "not_before" => froms.min, "not_after" => tos.max,
          "raw" => "VKS text_datefrom/text_dateto over #{years} dated text element#{'s' unless years == 1}" }
      end
    end
  end
end
