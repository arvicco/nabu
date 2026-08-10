# frozen_string_literal: true

require_relative "titus_avestan_parser"

module Nabu
  module Adapters
    # TITUS Avestan Corpus (P43-2) — the Avesta as served by TITUS (J. W.
    # Goethe-Universität Frankfurt, Prof. Jost Gippert), a preliminary electronic
    # edition on the basis of Geldner and Westergaard, prepared by Sonja Fritz
    # and corrected by Gippert et al.
    #
    # == The grant (№41-3) and the credit duty
    #
    # This corpus is fetched under the owner's PERSONAL grant (Gippert,
    # 2026-07-23): non-commercial use, with "TITUS and the editors clearly
    # indicated wherever displayed." Two mechanisms carry that:
    #   - the FETCH right (not conveyed by a public clone) → `grant_required: true`
    #     on the registry row arms the sync-time grant gate (Nabu::GrantGate);
    #   - the DISPLAY duty → license_class `nc` (non-commercial; NOT hidden — the
    #     grant wants it displayed, credited) plus the source-level +credit+ line
    #     in the manifest, threaded onto every serving surface.
    #
    # == Shape (see Nabu::Adapters::TitusAvestanParser)
    #
    # Frame-based site, sequential pages avest001.htm, avest002.htm, … linked by
    # "Next part". One PAGE is one document (the fetch's natural unit and the one
    # self-describing file the attic can rediscover); its verses are the
    # passages. Book context lives in the `<A NAME="Avest._<book>_<ch>_<par>_<v>">`
    # anchors, so a continuation page (no "Book:" header) still keys correctly.
    class TitusAvestan < Nabu::Adapter
      SLUG = "titus-avestan"
      LANGUAGE = "ave" # ISO-639 Avestan
      PARSER_FAMILY = "titus_avestan"

      # The frameset entry the fetch walks from; page files hang off the same dir.
      ENTRY_URL = "https://titus.uni-frankfurt.de/texte/etcs/iran/airan/avesta/avest.htm"

      LICENSE = "personal grant, Gippert 2026-07-23: non-commercial use; " \
                "TITUS and the editors clearly indicated wherever displayed"

      # The verbatim attribution the grant requires rendered wherever text shows.
      CREDIT = "TITUS (J. Gippert, Frankfurt) — Avesta ed. Geldner/Westergaard, " \
               "electronic text S. Fritz, corr. J. Gippert et al."

      # Numbered text pages (avest001.htm …); the frameset avest.htm is not one.
      PAGE_GLOB = "avest*.htm"
      PAGE_RE = /\Aavest\d+\.htm\z/

      # Human book names for the document title (display only; the anchor token
      # is the source of truth). Unknown codes fall back to the raw token.
      BOOK_NAMES = {
        "Y" => "Yasna", "Yt" => "Yašt", "V" => "Videvdad", "Vr" => "Visperad",
        "N" => "Nyayišn", "G" => "Gah", "S" => "Siroza", "A" => "Afrinagan",
        "H" => "Hadoxt Nask", "Aog" => "Aogəmadaēca", "P" => "Pursišniha"
      }.freeze

      # The Gathic chapter set of the Yasna (P66-1): the five Gathas
      # (Y 28-34, 43-51, 53) plus the Yasna Haptaŋhāiti (Y 35-41) — the
      # Old Avestan corpus by the standard scholarly division (Y 42 and 52
      # are Young Avestan insertions and fall outside the ranges). Every
      # other book (Yt, V, Vr, …) is Young Avestan. Ruled with №3
      # (2026-08-09, ave:old/yng minted upstream); the avestan-stage facet
      # this set derives is what the ave-stage lect rule attaches to.
      GATHIC_CHAPTERS = ((28..41).to_a + (43..51).to_a + [53]).freeze

      # The present structural levels, named — a verse carries all four, a
      # chapter-level rubric only book+chapter (deeper keys absent, not nil).
      SECTION_KEYS = %w[book chapter paragraph verse].freeze
      # Five components (P43-i2) mean a liturgical refrain rides between
      # paragraph and verse: book chapter paragraph REFRAIN verse.
      SECTION_KEYS_WITH_REFRAIN = %w[book chapter paragraph refrain verse].freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Avestan Corpus",
          license: LICENSE,
          license_class: "nc",
          upstream_url: ENTRY_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # Enumerate the fetched text pages as DocumentRefs (one per page). ref.id
      # IS the document urn (the conformance identity the sync breaker relies on).
      def discover(workdir)
        Dir.glob(File.join(workdir, PAGE_GLOB)).filter_map do |path|
          name = File.basename(path)
          next unless name.match?(PAGE_RE)

          stem = name.delete_suffix(".htm")
          Nabu::DocumentRef.new(source_id: SLUG, id: document_urn(stem), path: path,
                                metadata: { "page" => stem })
        end
      end

      # Parse one page into a Document of verse Passages. A page with content but
      # no keyable verses is a structural failure (ParseError) — quarantined
      # whole, never served with a hole.
      def parse(document_ref)
        html = File.read(document_ref.path, encoding: "UTF-8")
        sections = TitusAvestanParser.parse(html)
        raise Nabu::ParseError, "titus-avestan: no text sections in #{document_ref.path}" if sections.empty?

        # P66-1: the avestan-stage facet (old-avestan / young-avestan by the
        # GATHIC_CHAPTERS set; a page mixing both, or carrying no
        # chapter-keyed section, makes no claim). Rides metadata "facets"
        # (the coptic-scriptorium dialect shape) so the ave-stage lect rule
        # can read it.
        stage = self.class.avestan_stage(sections)
        metadata = stage ? { "facets" => { "avestan-stage" => { "value" => stage } } } : {}
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(document_ref.metadata["page"], sections), metadata: metadata
        )
        # P43-i2 (the owner's first full sync): the liturgy REPEATS — 48 of
        # the 248 live pages re-anchor an identical citation for a repeated
        # recitation (1,256 extra occurrences corpus-wide; Y.0.13's Q1c/Q1d
        # pairs are the fixture exemplar), which collided at Document#<<.
        # A repeat disambiguates as `<citation>#<occurrence>` in document
        # order (the P43-r2 kanripo shape) and carries the honest
        # "repetition" annotation — a repeated recitation is real text,
        # never a defect and never silently merged.
        seen = Hash.new(0)
        sections.each_with_index do |section, sequence|
          occurrence = (seen[section.components.join(".")] += 1)
          annotations = section_annotations(section)
          annotations["repetition"] = occurrence if occurrence > 1
          document << Nabu::Passage.new(
            urn: passage_urn(document_ref.id, section, occurrence), language: LANGUAGE,
            text: section.text, sequence: sequence,
            annotations: annotations
          )
        end
        document
      end

      # Polite sequential page walk from the frameset (owner-run; never in tests
      # — WebMock blocks the network). Delegates to Nabu::TitusFetch, which lands
      # each avestNNN.htm under +workdir+, pauses ≥2s between requests, is
      # resumable at the page grain, and honors the non-destructive attic
      # contract + the mass-deletion breaker.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::TitusFetch.sync!(
          entry_url: ENTRY_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue Nabu::TitusFetch::Error => e
        raise Nabu::FetchError, "titus-avestan fetch failed into #{workdir}: #{e.message}"
      end

      # One page's stage: every chapter-keyed section votes (non-Yasna books
      # are Young Avestan wholesale; Yasna chapters vote by GATHIC_CHAPTERS);
      # a unanimous page names its stage, anything mixed or voteless is nil —
      # the honest bare anchor. Public: the classification is a testable
      # claim, not plumbing.
      def self.avestan_stage(sections)
        votes = sections.filter_map do |section|
          book, chapter = section.components
          next "young" unless book == "Y"
          next nil if chapter.nil? || !chapter.match?(/\A\d+\z/)

          GATHIC_CHAPTERS.include?(chapter.to_i) ? "old" : "young"
        end.uniq
        votes.size == 1 ? "#{votes.first}-avestan" : nil
      end

      private

      def document_urn(stem)
        "urn:nabu:#{SLUG}:#{stem}"
      end

      # Passage urn nests under the document (page) urn — the house convention
      # (sefaria: <doc-urn>:<tail>) so `show`'s suffix labels work — with the
      # section's dotted citation as the tail: book[.chapter[.paragraph[.verse]]],
      # and `#<occurrence>` appended for a repeated recitation (P43-i2).
      def passage_urn(document_urn, section, occurrence = 1)
        tail = section.components.join(".")
        tail = "#{tail}##{occurrence}" if occurrence > 1
        "#{document_urn}:#{tail}"
      end

      def section_annotations(section)
        keys = section.components.size == 5 ? SECTION_KEYS_WITH_REFRAIN : SECTION_KEYS
        keys.zip(section.components).to_h.compact
      end

      def title_for(stem, sections)
        book = sections.first.components.first
        "Avestan Corpus — #{BOOK_NAMES.fetch(book, book)} (#{stem})"
      end
    end
  end
end
