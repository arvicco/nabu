# frozen_string_literal: true

require "json"

require_relative "../../adapters/aes"
require_relative "../../aed_text_headers"
require_relative "../../normalize"

module Nabu
  module Store
    module TimelineBuilder
      # AES text dates and findspots (P28-0): the corpus dates every
      # sentence with one of SIX coarse values (censused whole at fixture
      # time, 2026-07-18 — "OK & FIP" ×36,326 / "NK" ×33,177 /
      # "TIP - Roman times" ×16,426 / "MK & SIP" ×14,205 / "unknown" ×1,660
      # / degenerate "k" ×2), constant per text; findspot is one of 8
      # coarse regions. The OraccDates shape: a period vocabulary mapped to
      # conventional year envelopes, place verbatim, unmapped values
      # counted undated and never guessed.
      #
      # == The AED header grain (the tighter lane, preferred)
      #
      # canonical/aed holds a TEI header per TLA text (AedTextHeaders) —
      # the same text ids, 13,025 of the 13,026 AES texts. Its origDate
      # is a thesaurus label (ruler / dynasty / period / quarter-century)
      # with numeric bounds; its origPlace a SITE with a TLA thesaurus ref
      # ("Abusir", ths:O5AYJCUXENDODEGUIMCH2YWXWM). Each axis takes the
      # header's claim when it carries one and falls back to the corpus's
      # coarse value independently: date_raw is the header label, precision
      # its grain ("reign" / "dynasty" / "period" / "century" — told apart
      # from the coarse lane's "period" rows by the label itself),
      # place_ref the ths: ref VERBATIM (no registry namespace resolves
      # ths: yet — PlaceRefs reads it as nothing, honestly). Still ONE row
      # per text: the tighter claim replaces the coarse envelope rather
      # than riding beside it, so a narrow date search is never matched by
      # the wide period alone. date_class stays NULL: both lanes date the
      # object (the inscribed monument or papyrus), not a composition era.
      #
      # The urn mint mirrors Adapters::Aes#discover (FROZEN): subcorpus
      # from the filename + the sentence's own text id; the test pins the
      # two against each other via the shared fixture set. -de siblings
      # never join (their urns carry the -de suffix, no text id mints it).
      module AesDates
        SLUG = "aes"
        URN_PREFIX = "urn:nabu:aes:"
        AED_SLUG = "aed"

        # Egyptian period value → signed year envelope, CONVENTIONAL
        # Egyptological chronology (after Shaw (ed.), The Oxford History of
        # Ancient Egypt, 2000 — the accepted ca. bounds; the corpus's own
        # thesaurus, doi 10.5281/zenodo.3581069, defines the vocabulary but
        # assigns no absolute years). All bounds are honest "ca." ranges —
        # periodisation is convention, not measurement:
        #   OK & FIP          Old Kingdom + First Intermediate Period
        #   MK & SIP          Middle Kingdom + Second Intermediate Period
        #   NK                New Kingdom
        #   TIP - Roman times Third Intermediate Period through Roman Egypt
        #                     (bounded at 395 CE, the conventional end of
        #                     Roman rule over Egypt)
        PERIODS = {
          "OK & FIP" => [-2686, -2025],
          "MK & SIP" => [-2055, -1550],
          "NK" => [-1550, -1069],
          "TIP - Roman times" => [-1069, 395]
        }.freeze

        module_function

        # Walk canonical/aes's subcorpus files and insert one row per
        # dated-or-placed text we hold; texts we hold whose date AND place
        # are both unmapped are counted undated. Returns
        # { documents:, undated:, aed: } — aed counts the rows that took
        # at least one axis from the AED header.
        def build(catalog:, canonical_dir:)
          dir = File.join(canonical_dir, SLUG, Adapters::Aes::DATA_DIR)
          return { documents: 0, undated: 0, aed: 0 } unless Dir.exist?(dir)

          headers = AedTextHeaders.new(aed_dir: File.join(canonical_dir, AED_SLUG))
          ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          counts = { documents: 0, undated: 0, aed: 0 }
          each_text(dir) do |urn, sentence|
            document_id = ids[urn] or next
            timeline = extract(sentence, headers.header(sentence["text"].to_s))
            if timeline.nil?
              counts[:undated] += 1
              next
            end

            insert(catalog, document_id, timeline)
            counts[:documents] += 1
            counts[:aed] += 1 if timeline[:aed]
          end
          counts
        end

        # Yields [document urn, first sentence] per text — date/findspot
        # are constant per text (censused), so the first sentence carries
        # the whole story.
        def each_text(dir)
          Dir.glob(File.join(dir, "_aes_*.json")).each do |path|
            subcorpus = File.basename(path)[/\A_aes_(.+)\.json\z/, 1]
            seen = {}
            JSON.parse(File.read(path)).each_value do |sentence|
              text_id = sentence["text"].to_s
              next if text_id.empty? || seen.key?(text_id)

              seen[text_id] = true
              yield "#{URN_PREFIX}#{subcorpus}:#{text_id}", sentence
            end
          end
        end

        # Every original-text urn the extractor would mint from +workdir+'s
        # data files (the drift-pin hook the timeline test compares against the
        # adapter's discover).
        def text_urns(workdir)
          urns = []
          each_text(File.join(workdir, Adapters::Aes::DATA_DIR)) { |urn, _sentence| urns << urn }
          urns
        end

        # The timeline fields, or nil when neither a date nor a place
        # survives (unknown/"k" with no usable header — the honest undated
        # case). +header+ is the text's AedTextHeaders::Header or nil; each
        # axis prefers it and falls back to the coarse corpus value alone.
        def extract(sentence, header = nil)
          header_date = header&.date_raw
          header_place = header&.place_name
          date = header_date ? aed_date(header) : coarse_date(sentence)
          place = header_place ? [header_place, header.place_ref] : [place_of(sentence), nil]
          return nil if date.nil? && place.first.nil?

          (date || {}).merge(place_name: place.first, place_ref: place.last,
                             aed: !(header_date.nil? && header_place.nil?))
        end

        def aed_date(header)
          { not_before: header.not_before, not_after: header.not_after,
            precision: header.precision, date_raw: header.date_raw }
        end

        def coarse_date(sentence)
          date = sentence["date"].to_s
          bounds = PERIODS[date] or return nil

          { not_before: bounds.first, not_after: bounds.last, precision: "period", date_raw: date }
        end

        def place_of(sentence)
          findspot = sentence["findspot"].to_s
          return nil unless Adapters::Aes::FINDSPOT_FACETS.key?(findspot)

          Nabu::Normalize.nfc(findspot)
        end

        def insert(catalog, document_id, timeline)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: timeline[:not_before], not_after: timeline[:not_after],
            precision: timeline[:precision], date_raw: timeline[:date_raw],
            place_name: timeline[:place_name], place_ref: timeline[:place_ref], axis_source: SLUG
          )
        end
      end
    end
  end
end
