# frozen_string_literal: true

require_relative "wiktionary_jsonl_parser"

module Nabu
  module Adapters
    # The reconstruction shelf source (P14-1, architecture §12; extended
    # P17-3, P25-2, P29-0, P29-1, P32-5): English Wiktionary's reconstruction
    # pseudo-languages — plus, since P25-2, ATTESTED languages — via the
    # kaikki.org wiktextract extraction. ONE source shipping THIRTEEN
    # dictionaries (Proto-Slavic sla-pro, Proto-Indo-European ine-pro,
    # Proto-Germanic gem-pro; P17-3 adds Proto-Balto-Slavic ine-bsl-pro,
    # Proto-West Germanic gmw-pro, Proto-Italic itc-pro, Proto-Indo-Iranian
    # iir-pro; P25-2 adds Old Irish sga, Middle Irish mga, Middle Welsh
    # wlm; P29-1 adds Umbrian xum — the CEIPoM rider, the only
    # kaikki-served Italic corpus language; P29-0 adds Etruscan ett —
    # whose descendants trees carry the Etruscan→Latin loan edges;
    # P32-5 adds Old Japanese ojp — the Sino-axis desk beside ONCOJ's
    # corpus attestations),
    # each its own JSONL through the SAME wiktionary-jsonl family
    # as wiktionary-cu, with `reflexes: true`: the records' `descendants`
    # trees flatten into DictionaryReflex edges — the crosswalk that links
    # reconstructed headwords to attested in-catalog lemmas (`nabu etym`).
    # ine-bsl-pro and gmw-pro are INTERMEDIATE shelves (PIE → PBS →
    # Proto-Slavic; Proto-Germanic → PWG → Old English) — the shelves whose
    # arrival replaced the closure's one-hop ascent with the shelf-visited
    # multi-hop walk (Store::ReflexRootsIndexer). The attested Celtic
    # extracts ride the wiktionary-cu precedent (P16-5: attested entries
    # mint reflex edges too, no display asterisk): an sga entry's
    # descendants reach mga/ga/gd/gv, so the shelf-visited walk ascends
    # Middle Irish → Old Irish, and the DIL-derived sga etymology text
    # (Proto-Celtic/PIE chains) is KEPT verbatim in entry bodies.
    #
    # == Upstream (verified page-level + ranged reads, docs/backlog.md P14-1
    # Phase A, 2026-07-12; P17-3 survey .docs/surveys/recon2-survey.md, 2026-07-13;
    # P25-2 Celtic survey .docs/surveys/celtic-survey.md, 2026-07-16;
    # full downloads at fixture builds)
    #
    # kaikki.org per-language extracts, built from the enwiktionary dump
    # dated 2026-07-06 (wiktextract, Tatu Ylönen): Proto-Slavic 47.6 MB /
    # 5,431 records, PIE 12.0 MB / 1,905, Proto-Germanic 65.3 MB / 5,717;
    # P17-3 (2026-07-13): Proto-Balto-Slavic 1.7 MB / 491, Proto-West
    # Germanic 49.4 MB / 5,551, Proto-Italic 5.2 MB / 745,
    # Proto-Indo-Iranian 3.3 MB / 799; P25-2 (2026-07-17): Old Irish
    # 19.8 MB / 6,564 records (5,828 distinct words; 2,093 with
    # descendants, 1,427 with a Proto-Celtic etymology), Middle Irish
    # 1.3 MB / 767 (710 distinct), Middle Welsh 1.3 MB / 766 (695
    # distinct). The `word` field carries NO asterisk on the proto shelves
    # (display prefixes it back); `lang_code` is the Wiktionary
    # etymology-language code the registry adopts verbatim (conventions §4:
    # the -pro codes are not ISO 639-3, but pass the shape-only tag
    # validation unchanged; sga/mga/wlm ARE ISO 639-3 and pass as
    # themselves).
    #
    # DEPRECATION CAVEAT: like the OCS extract, the per-language JSONL is
    # labelled "DEPRECATED, will be removed in the near future" (wiktextract
    # issue #1178) yet is what the site itself serves. A future 404 is a
    # clean FetchError; the durable fallback is filtering the full
    # enwiktionary extract by lang_code — recorded in docs/02-sources.md.
    #
    # == License
    #
    # Verbatim, https://kaikki.org/dictionary/ "Copyright and license"
    # (re-verified 2026-07-12): "This data is made available under the same
    # licenses as Wiktionary - both CC-BY-SA and GFDL." → attribution,
    # MCP-surface-safe; wiktextract asks for the academic citation (Ylönen,
    # LREC 2022) — carried in 02-sources.
    #
    # == fetch / sync policy
    #
    # Thirteen FileFetch single-file syncs, one per extract, each in ITS OWN
    # subdir (FileFetch is one-file-per-dir by design: any other file in
    # the dir is doomed, and there is one state file per dir), attics under
    # the shared top-level <workdir>/.attic/<subdir>/ so discover_with_attic
    # finds retained files — the UD multi-repo choreography: ALL extracts
    # prepare (tree untouched), the mass-deletion breaker sees the whole
    # SET, then all complete. sync_policy: manual; the P17-3 extracts land
    # in the live catalog at the next owner-fired sync (~60 MB across the
    # four new GETs, +7,586 entries); likewise the P25-2 Celtic extracts
    # (~22.4 MB across three GETs, +8,097 entries) and the P32-5 Old
    # Japanese extract (one ~1.26 MB GET, +532 entries).
    class WiktionaryRecon < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-recon",
        name: "Wiktionary reconstructions + attested Celtic, Italic, Etruscan and Old Japanese — " \
              "kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, " \
              "Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, " \
              "Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, " \
              "Old Japanese)",
        license: "CC-BY-SA + GFDL (verbatim kaikki.org/dictionary/: \"This data is made available " \
                 "under the same licenses as Wiktionary - both CC-BY-SA and GFDL.\")",
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/",
        parser_family: "wiktionary-jsonl"
      )

      # One dictionary per extract; iteration order is registry order
      # (discover/parse/probe all speak it). Slugs mint the urn namespaces
      # (urn:nabu:dict:wiktionary-sla-pro:<entry_id>); `language` is the
      # Wiktionary etymology-language code adopted verbatim.
      EXTRACTS = {
        "wiktionary-sla-pro" => {
          subdir: "proto-slavic",
          filename: "kaikki.org-dictionary-ProtoSlavic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Slavic/kaikki.org-dictionary-ProtoSlavic.jsonl",
          language: "sla-pro",
          title: "Wiktionary — Proto-Slavic (kaikki.org extract)"
        }.freeze,
        "wiktionary-ine-pro" => {
          subdir: "proto-indo-european",
          filename: "kaikki.org-dictionary-ProtoIndoEuropean.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Indo-European/" \
               "kaikki.org-dictionary-ProtoIndoEuropean.jsonl",
          language: "ine-pro",
          title: "Wiktionary — Proto-Indo-European (kaikki.org extract)"
        }.freeze,
        "wiktionary-gem-pro" => {
          subdir: "proto-germanic",
          filename: "kaikki.org-dictionary-ProtoGermanic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Germanic/kaikki.org-dictionary-ProtoGermanic.jsonl",
          language: "gem-pro",
          title: "Wiktionary — Proto-Germanic (kaikki.org extract)"
        }.freeze,
        # -- P17-3 (recon shelf part 2; survey .docs/surveys/recon2-survey.md §5) --
        "wiktionary-ine-bsl-pro" => {
          subdir: "proto-balto-slavic",
          filename: "kaikki.org-dictionary-ProtoBaltoSlavic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Balto-Slavic/" \
               "kaikki.org-dictionary-ProtoBaltoSlavic.jsonl",
          language: "ine-bsl-pro",
          title: "Wiktionary — Proto-Balto-Slavic (kaikki.org extract)"
        }.freeze,
        "wiktionary-gmw-pro" => {
          subdir: "proto-west-germanic",
          filename: "kaikki.org-dictionary-ProtoWestGermanic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-West%20Germanic/" \
               "kaikki.org-dictionary-ProtoWestGermanic.jsonl",
          language: "gmw-pro",
          title: "Wiktionary — Proto-West Germanic (kaikki.org extract)"
        }.freeze,
        "wiktionary-itc-pro" => {
          subdir: "proto-italic",
          filename: "kaikki.org-dictionary-ProtoItalic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Italic/kaikki.org-dictionary-ProtoItalic.jsonl",
          language: "itc-pro",
          title: "Wiktionary — Proto-Italic (kaikki.org extract)"
        }.freeze,
        "wiktionary-iir-pro" => {
          subdir: "proto-indo-iranian",
          filename: "kaikki.org-dictionary-ProtoIndoIranian.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Indo-Iranian/" \
               "kaikki.org-dictionary-ProtoIndoIranian.jsonl",
          language: "iir-pro",
          title: "Wiktionary — Proto-Indo-Iranian (kaikki.org extract)"
        }.freeze,
        # -- P25-2 (Celtic axis; survey .docs/surveys/celtic-survey.md) --
        # ATTESTED languages on the recon source (the wiktionary-cu
        # precedent: attested entries mint reflex edges too, and render
        # without the display asterisk — codes carry no -pro suffix).
        "wiktionary-sga" => {
          subdir: "old-irish",
          filename: "kaikki.org-dictionary-OldIrish.jsonl",
          url: "https://kaikki.org/dictionary/Old%20Irish/kaikki.org-dictionary-OldIrish.jsonl",
          language: "sga",
          title: "Wiktionary — Old Irish (kaikki.org extract)"
        }.freeze,
        "wiktionary-mga" => {
          subdir: "middle-irish",
          filename: "kaikki.org-dictionary-MiddleIrish.jsonl",
          url: "https://kaikki.org/dictionary/Middle%20Irish/kaikki.org-dictionary-MiddleIrish.jsonl",
          language: "mga",
          title: "Wiktionary — Middle Irish (kaikki.org extract)"
        }.freeze,
        "wiktionary-wlm" => {
          subdir: "middle-welsh",
          filename: "kaikki.org-dictionary-MiddleWelsh.jsonl",
          url: "https://kaikki.org/dictionary/Middle%20Welsh/kaikki.org-dictionary-MiddleWelsh.jsonl",
          language: "wlm",
          title: "Wiktionary — Middle Welsh (kaikki.org extract)"
        }.freeze,
        # -- P29-1 rider (the CEIPoM Italic axis): Umbrian, the only
        # kaikki-served Italic corpus language (500 records, 373 with
        # etymology_text, 30 romanization stubs; 1.13 MB; census
        # 2026-07-18). Attested, the P25-2 pattern verbatim; Old Italic
        # headwords ride in real U+10300-block codepoints (𐌀𐌛𐌄𐌐𐌄𐌔).
        "wiktionary-xum" => {
          subdir: "umbrian",
          filename: "kaikki.org-dictionary-Umbrian.jsonl",
          url: "https://kaikki.org/dictionary/Umbrian/kaikki.org-dictionary-Umbrian.jsonl",
          language: "xum",
          title: "Wiktionary — Umbrian (kaikki.org extract)"
        },
        # -- P29-0 (the Etruscan axis; OpenEtruscan packet rider) --
        # ATTESTED, the wiktionary-cu precedent again (no display
        # asterisk; ett is real ISO 639-3). 493 records / 485 distinct
        # words at fixture time (419 Old Italic-script headwords, 73
        # romanization stubs), 179 with etymology_text; the descendants
        # trees carry the Etruscan→Latin LOAN edges (11 lat edges, 8
        # upstream-flagged borrowed: persōna, lanista, Carthāgō…) — the
        # P17-3 borrowed machinery mints them with zero new code.
        "wiktionary-ett" => {
          subdir: "etruscan",
          filename: "kaikki.org-dictionary-Etruscan.jsonl",
          url: "https://kaikki.org/dictionary/Etruscan/kaikki.org-dictionary-Etruscan.jsonl",
          language: "ett",
          title: "Wiktionary — Etruscan (kaikki.org extract)"
        }.freeze,
        # -- P32-5 (the Sino axis opens): Old Japanese, ATTESTED, the
        # P25-2 pattern verbatim (no display asterisk; ojp is real ISO
        # 639-3). 532 records / 413 distinct words at fixture time
        # (2026-07-19): 390 with etymology_text (87 naming Proto-Japonic),
        # 178 records quoting the Man'yōshū in sense examples (raw-record
        # density only — Wiktionary quotations are unanchored, citations
        # stay empty per the family contract); 301 with descendants → 333
        # worded edges (327 ja + 2 ain + 1 ltc + 1 en). etymology_number
        # is a STRING in this extract ("1"/"2"; integers everywhere else)
        # — the parser interpolates either, entry_ids unchanged.
        "wiktionary-ojp" => {
          subdir: "old-japanese",
          filename: "kaikki.org-dictionary-OldJapanese.jsonl",
          url: "https://kaikki.org/dictionary/Old%20Japanese/kaikki.org-dictionary-OldJapanese.jsonl",
          language: "ojp",
          title: "Wiktionary — Old Japanese (kaikki.org extract)"
        }.freeze
      }.freeze

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The parser runs with `reflexes: true` (P14-1): descendants become
      # dictionary_reflexes rows. Health checks this promise (P18-7).
      def self.reflex_bearing? = true

      # One HEAD per extract, each against its own subdir's FileFetch state
      # (Last-Modified drift + the DEPRECATED-file early warning).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        EXTRACTS.values.map do |extract|
          Nabu::Adapter::HttpProbeTarget.new(
            label: extract.fetch(:filename), zip_url: extract.fetch(:url), metadata_url: nil,
            state_subdir: extract.fetch(:subdir), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # One DocumentRef per extract file, in EXTRACTS order. A workdir
      # without a file simply yields fewer refs (the day-one pre-fetch
      # state); the same walk works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        EXTRACTS.each do |slug, extract|
          Dir.glob(File.join(workdir, "**", extract.fetch(:filename))).first(1).each do |path|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "#{slug}:#{extract.fetch(:filename)}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        extract = EXTRACTS.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: extract.fetch(:language),
          title: extract.fetch(:title), canonical_path: document_ref.path
        )
        WiktionaryJsonlParser.new(language: extract.fetch(:language), reflexes: true)
                             .entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "wiktionary-recon: #{document_ref.id}: #{e.message}"
      end

      # Download the extracts two-phase (the UD choreography): all
      # prepare with the live tree untouched, the breaker sees the combined
      # doomed set, then all complete. Report: last extract's sha (the
      # single-pin convention), per-extract shas in notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "wiktionary-recon fetch failed into #{workdir}: #{e.message}"
      end

      private

      def file_fetches(workdir, progress)
        EXTRACTS.transform_values do |extract|
          Nabu::FileFetch.new(
            url: extract.fetch(:url), dir: File.join(workdir, extract.fetch(:subdir)),
            filename: extract.fetch(:filename),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, extract.fetch(:subdir)),
            progress: progress
          )
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map do |slug, fetch|
          "#{EXTRACTS.fetch(slug).fetch(:language)} #{fetch.sha[0, 8]}"
        end
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
