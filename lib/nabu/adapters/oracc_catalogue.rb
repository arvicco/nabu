# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # One ORACC catalogue member → the document metadata it holds beyond
    # the designation/period/genre the Oracc adapter always read
    # (title + the period/genre facets). Censused 2026-10-18 over the
    # 125,738 members of the held build; every field rides VERBATIM (NFC)
    # under its upstream key unless noted — the value IS the claim
    # ("(unknown)" authors and "unattributed" rulers included).
    #
    # - PERSONS, with their roles in the key: ruler 12,689 · ancient_author
    #   3,967 · ancient_recipient 3,065 · dossier_list 2,357 · eponym
    #   1,123 · the legal parties seal_owner/ancient_buyer/ancient_seller/
    #   ancient_creditor/ancient_debtor (~215), which upstream joins with
    #   ";" and so ride as ARRAYS. These feed metadata + facets
    #   (config/facet_map.yml) — deliberately NOT person_index, which holds
    #   prosopography authorities with stable ids; a catalogue name string
    #   is not one.
    # - WORKS identity: id_composite (9,206 Q-numbers) · title → work_title
    #   (5,437; "(no title)" is upstream's placeholder, not a title — and
    #   the key avoids the ref's own "title", which is the designation) ·
    #   popular_name 3,389 · rime_no 1,640 · Q_designation 151 ·
    #   other_names (+ cmawro's qcat_2__other_names, the same claim under
    #   another key; ARRAY) · series / series_tablet_no.
    # - CONTEXT: subgenre 39,855 · supergenre 108,381 (both metadata +
    #   facets; NOT folded onto the kind axis — supergenre restates genre
    #   on 99.9% of members and its LIT spans royal inscriptions, subgenre
    #   mixes series names, rulers and archives) · archive 9,222 ·
    #   excavation_no 14,324 · findspot_square 3,412 (an excavation grid
    #   square — sub-site grain, below the place axis) · regnal_dates 4,359
    #   (also banded by TimelineBuilder::OraccDates) · dynastic_seat 5,411
    #   (the ruler's political seat — no ruled band table dates it, and it
    #   is not the text's place: metadata + facet only).
    # - The SAA SENDER place: sender_loc · pleiades_sender_loc ·
    #   sender_loc_coordinates (1,733 with coordinates) — metadata here,
    #   and its own labeled place row via OraccDates (axis_source
    #   "oracc-sender"); the "not assigned"/"N/A" placeholders are no value.
    #
    # Edges (#related): every composite Q-number (id_composite,
    # qcat_2__id_composite, composites) mints urn:nabu:cdli:q… — the SAME
    # hub target CDLI's composite_id mints, so ORACC witnesses, CDLI
    # witnesses and the composite meet at one hub.
    module OraccCatalogue
      SINGLE_FIELDS = %w[ruler ancient_author ancient_recipient dossier_list eponym
                         id_composite popular_name rime_no Q_designation series series_tablet_no
                         subgenre supergenre archive excavation_no findspot_square
                         regnal_dates dynastic_seat sender_loc].freeze

      # Upstream ";"-joined party lists.
      LIST_FIELDS = %w[seal_owner ancient_buyer ancient_seller ancient_creditor ancient_debtor].freeze

      # The sender-place identifiers whose placeholders are no value.
      SENDER_ID_FIELDS = %w[pleiades_sender_loc sender_loc_coordinates].freeze
      PLACEHOLDERS = ["not assigned", "N/A"].freeze

      NO_TITLE = "(no title)"

      COMPOSITE_FIELDS = %w[id_composite qcat_2__id_composite composites].freeze
      CDLI_PREFIX = "urn:nabu:cdli:"

      module_function

      def document_metadata(member)
        metadata = {}
        SINGLE_FIELDS.each { |field| put(metadata, field, value_of(member[field])) }
        LIST_FIELDS.each do |field|
          parties = strings(member[field]).flat_map { |value| value.split(";") }.map(&:strip).reject(&:empty?)
          metadata[field] = parties unless parties.empty?
        end
        title = value_of(member["title"])
        metadata["work_title"] = title unless title.nil? || title == NO_TITLE
        names = (strings(member["other_names"]) + strings(member["qcat_2__other_names"])).uniq
        metadata["other_names"] = names unless names.empty?
        SENDER_ID_FIELDS.each do |field|
          value = value_of(member[field])
          metadata[field] = value unless value.nil? || PLACEHOLDERS.include?(value)
        end
        metadata
      end

      def related(member)
        COMPOSITE_FIELDS.flat_map { |field| strings(member[field]) }
                        .flat_map { |value| value.scan(/Q\d{6}/) }
                        .map { |q| "#{CDLI_PREFIX}#{q.downcase}" }.uniq
      end

      # A scalar field's value: a string verbatim, an array kept as an
      # array (never flattened into a string), nil when empty.
      def value_of(raw)
        return nil if raw.nil?

        values = strings(raw)
        return nil if values.empty?

        raw.is_a?(Array) ? values : values.first
      end

      def strings(raw)
        Array(raw).filter_map do |value|
          next unless value.is_a?(String) || value.is_a?(Numeric)

          text = Normalize.nfc(value.to_s.strip)
          text unless text.empty?
        end
      end

      def put(metadata, field, value)
        metadata[field] = value unless value.nil?
      end
    end
  end
end
