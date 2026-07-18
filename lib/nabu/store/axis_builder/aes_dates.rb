# frozen_string_literal: true

require "json"

require_relative "../../adapters/aes"
require_relative "../../normalize"

module Nabu
  module Store
    module AxisBuilder
      # AES text dates and findspots (P28-0): the corpus dates every
      # sentence with one of SIX coarse values (censused whole at fixture
      # time, 2026-07-18 — "OK & FIP" ×36,326 / "NK" ×33,177 /
      # "TIP - Roman times" ×16,426 / "MK & SIP" ×14,205 / "unknown" ×1,660
      # / degenerate "k" ×2), constant per text; findspot is one of 8
      # coarse regions. The OraccDates shape: a period vocabulary mapped to
      # conventional year envelopes, place verbatim, unmapped values
      # counted undated and never guessed.
      #
      # The urn mint mirrors Adapters::Aes#discover (FROZEN): subcorpus
      # from the filename + the sentence's own text id; the test pins the
      # two against each other via the shared fixture set. -de siblings
      # never join (their urns carry the -de suffix, no text id mints it).
      module AesDates
        SLUG = "aes"
        URN_PREFIX = "urn:nabu:aes:"

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
        # { documents:, undated: }.
        def build(catalog:, canonical_dir:)
          dir = File.join(canonical_dir, SLUG, Adapters::Aes::DATA_DIR)
          return { documents: 0, undated: 0 } unless Dir.exist?(dir)

          ids = catalog[:documents].where(Sequel.like(:urn, "#{URN_PREFIX}%")).select_hash(:urn, :id)
          rows = 0
          undated = 0
          each_text(dir) do |urn, sentence|
            document_id = ids[urn] or next
            axis = extract(sentence)
            if axis.nil?
              undated += 1
              next
            end

            insert(catalog, document_id, axis)
            rows += 1
          end
          { documents: rows, undated: undated }
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
        # data files (the drift-pin hook the axis test compares against the
        # adapter's discover).
        def text_urns(workdir)
          urns = []
          each_text(File.join(workdir, Adapters::Aes::DATA_DIR)) { |urn, _sentence| urns << urn }
          urns
        end

        # The axis fields, or nil when neither the date nor the findspot
        # maps (unknown/"k" — the honest undated case).
        def extract(sentence)
          date = sentence["date"].to_s
          bounds = PERIODS[date]
          place = place_of(sentence)
          return nil if bounds.nil? && place.nil?

          {
            not_before: bounds&.first, not_after: bounds&.last,
            precision: bounds ? "period" : nil, date_raw: bounds ? date : nil,
            place_name: place
          }
        end

        def place_of(sentence)
          findspot = sentence["findspot"].to_s
          return nil unless Adapters::Aes::FINDSPOT_FACETS.key?(findspot)

          Nabu::Normalize.nfc(findspot)
        end

        def insert(catalog, document_id, axis)
          catalog[:document_axes].insert(
            document_id: document_id,
            not_before: axis[:not_before], not_after: axis[:not_after],
            precision: axis[:precision], date_raw: axis[:date_raw],
            place_name: axis[:place_name], axis_source: SLUG
          )
        end
      end
    end
  end
end
