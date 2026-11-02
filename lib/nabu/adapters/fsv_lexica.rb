# frozen_string_literal: true

require_relative "spraakbanken_lmf_parser"

module Nabu
  module Adapters
    # fsv-lexica: Språkbanken's (University of Gothenburg) three Old
    # Swedish dictionaries as three shelves of one source — the
    # dictionaries for the held fornsvenska corpus (same host):
    #
    # - soederwall: K.F. Söderwall, Ordbok öfver svenska medeltids-språket
    #   (1884–1918) — "Lexikonet består av K.F. Söderwalls Ordbok Öfver
    #   svenska medeltids-språket." 22,572 entries; keyed by hand, headwords
    #   proofread after keying, the article bodies not (the resource
    #   page). DOI 10.23695/0gf3-5042.
    # - soederwall-supp: the supplement (Söderwall, Åkerlund, Ljunggren,
    #   Wessén, 1925–1973) — 19,172 entries; headwords AND articles not
    #   proofread after keying ("Uppslagsorden och övriga delar av
    #   ordboksartiklarna är inte kontrollästa efter inkodningen").
    #   DOI 10.23695/vp9e-pg93.
    # - schlyter: C.J. Schlyter, Ordbok till Samlingen af Sweriges Gamla
    #   Lagar (1877) — the glossary of the medieval provincial and town
    #   laws (fornsvenska's aldrelagar/yngrelagar slices); 10,067 entries;
    #   not proofread after keying. DOI 10.23695/mpem-ah13.
    #
    # Stored language sv (the held fornsvenska text's own tag; the
    # dictionary-language filter widens it to swe); the per-source lect
    # override in config/lect_overrides.yml resolves the shelves to the
    # sv:old stage — the books' object is the medieval language by title.
    #
    # == Upstream / grains (verified 2026-11-02)
    #
    # Each resource page (spraakbanken.gu.se/resurser/<id>) serves ONE
    # download, the Karp LMF export (svn.spraakbanken.gu.se/sb-arkiv/pub/
    # lmf/<id>/<id>.xml, last modified 2017-09-19) — each ACCEPTED whole
    # as one dictionary document; the Karp web view (karp-red) is the
    # same data, not fetched. Reconciliation against the pages' own
    # "Ingångar" counts, exact: 22,572 / 19,172 / 10,067 LexicalEntry
    # records, every one with a lemgram, lemgrams unique per file.
    # Quality, declared: the books were keyed by hand and only Söderwall's
    # headwords were proofread — the bodies carry keying noise (Schlyter's
    # "!GREKISKA?" placeholders where Greek was not keyed, 23 entries;
    # print hyphenation kept, "säl- jaren"; head-line grammar keyed into
    # writtenForm); the headword is therefore the lemgram's baseform
    # (SpraakbankenLmfParser note). Entries with no article text at all
    # (30 / 49 / 0) keep their head line as the body. Census through the
    # house parser: 51,811 entries, glossless 467 / 649 / 2.
    #
    # == License
    #
    # Each resource page, verbatim: "CC-BY-4.0" (read 2026-11-02); the
    # pages ask for citation of the dataset with its DOI ("Bearbetad och
    # distribuerad av Språkbanken"). Söderwall's main work and Schlyter
    # are public domain by age; the supplement (completed 1973) is not,
    # and rides Språkbanken's own CC BY 4.0 grant → license_class
    # "attribution".
    class FsvLexica < Nabu::Adapter
      LMF_BASE = "https://svn.spraakbanken.gu.se/sb-arkiv/pub/lmf"

      DICTIONARIES = {
        "soederwall" => {
          title: "Söderwall, Ordbok öfver svenska medeltids-språket (1884–1918)",
          doi: "10.23695/0gf3-5042"
        },
        "soederwall-supp" => {
          title: "Söderwall, Ordbok öfver svenska medeltids-språket — Supplement (1925–1973)",
          doi: "10.23695/vp9e-pg93"
        },
        "schlyter" => {
          title: "Schlyter, Ordbok till Samlingen af Sweriges Gamla Lagar (1877)",
          doi: "10.23695/mpem-ah13"
        }
      }.freeze

      LANGUAGE = "sv"

      MANIFEST = Nabu::SourceManifest.new(
        id: "fsv-lexica",
        name: "Språkbanken Old Swedish dictionaries — Söderwall, Söderwall supplement, Schlyter (Karp LMF)",
        license: "CC-BY-4.0 (verbatim, each Språkbanken resource page: \"CC-BY-4.0\"; cite the datasets " \
                 "by DOI 10.23695/0gf3-5042, 10.23695/vp9e-pg93, 10.23695/mpem-ah13); " \
                 "Söderwall 1884–1918 and Schlyter 1877 are public domain",
        license_class: "attribution",
        upstream_url: "https://spraakbanken.gu.se/resurser/soederwall",
        parser_family: "spraakbanken-lmf"
      )

      def self.manifest = MANIFEST

      # Entries, not passages — SyncRunner/Rebuild load through
      # Store::DictionaryLoader (architecture §11).
      def self.content_kind = :dictionary

      def self.url_for(slug) = "#{LMF_BASE}/#{slug}/#{slug}.xml"

      def self.filename(slug) = "#{slug}.xml"

      # One HEAD per LMF file against its subdir's FileFetch state.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        DICTIONARIES.keys.map do |slug|
          Nabu::Adapter::HttpProbeTarget.new(
            label: filename(slug), zip_url: url_for(slug), metadata_url: nil,
            state_subdir: slug, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        DICTIONARIES.each_key do |slug|
          path = File.join(workdir, slug, self.class.filename(slug))
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{slug}:#{self.class.filename(slug)}",
            path: File.expand_path(path), metadata: { "dictionary" => slug }
          )
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: LANGUAGE, title: DICTIONARIES.fetch(slug).fetch(:title),
          canonical_path: document_ref.path
        )
        SpraakbankenLmfParser.new(language: LANGUAGE).entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "fsv-lexica: #{document_ref.id}: #{e.message}"
      end

      # The three files two-phase (the wiktionary-recon choreography): all
      # prepare with the live tree untouched, the breaker sees the combined
      # doomed set, then all complete.
      def fetch(workdir, progress: nil, force: false)
        fetches = DICTIONARIES.keys.to_h do |slug|
          [slug, Nabu::FileFetch.new(
            url: self.class.url_for(slug), dir: File.join(workdir, slug), filename: self.class.filename(slug),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, slug), progress: progress
          )]
        end
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        notes = fetches.map { |slug, f| "#{slug} #{f.sha[0, 8]}" }.join(" · ")
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: [notes, attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; "))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "fsv-lexica fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
