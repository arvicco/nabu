# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_char tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      CHAR_DESCRIPTION =
        "The sign/character desk card (P65/P68): ONE glyph or sign identity in, the full held " \
        "identity out — the same frozen contracts as `nabu char --json`. Dispatch by input: a " \
        "CUNEIFORM glyph (𒊬, compounds included) or sign name/value/list number (SAR · szesz " \
        "· idx — trailing x reads as ₓ · MZL535 · bare 852 across every held list) serves the " \
        "Oracc Sign List card: name, @aka, MZL/LAK/ABZL/HZL/ŠL concordances, values by " \
        "language, CDLI meaning glosses, Wiktionary senses, variant forms, corpus counts; an " \
        "ambiguous value lists ALL candidate signs, never one silently. An EGYPTIAN HIEROGLYPH " \
        "(𓅃) or Gardiner-style code (G5, N35) serves the Unikemet card: catalog code, " \
        "description, function, phonetic value, JSesh/Hieroglyphica/IFAO concordances, aes " \
        "attestation. The Han character card is CLI-only for now — answered with a note " \
        "(nabu_define serves Han dictionary entries meanwhile). Absent data is null/[], " \
        "never a placeholder. Every card names its reference spine — `source`, " \
        "`license_class`, `license` (OSL CC0, Unikemet Unicode License) — and `attribution` " \
        "lists every contributing dataset; PRESERVE them when quoting."

      CHAR_SCHEMA = {
        type: "object",
        properties: {
          query: { type: "string",
                   description: "A glyph (𒊬 · 𓅃), a sign name or spelled value (SAR · " \
                                "szesz · idx), a sign-list number (MZL535 · 852), or a " \
                                "Gardiner-style code (G5)." }
        },
        required: ["query"]
      }.freeze

      private

      # nabu_signs (P53-2): the sign desk — Query::Signs unchanged under the
      # MCP shape, serving the SAME frozen JSON contract as the CLI's --json
      # (one serializer, Query::Signs.json_payload). Degradation split: an
      # absent sign list / absent corpus is a corpus STATE (note — the owner
      # syncs osl, not the caller); urn-XOR-text and a bad dialect are
      # caller-fixable (InvalidArguments, SEP-1303). Urn mode passes the
      # restricted-exclusion gate; raw text touches no catalog.
      # The sign/character card (P68-3): the P65 CLI `--json` contracts
      # served verbatim — SignCard for cuneiform lanes, HieroCard for
      # hieroglyph lanes, dispatch by CharDispatch, the CLI's name-lane
      # order (OSL first, then Gardiner code). A Han glyph notes the
      # missing contract (matching `char --json`); an unmatched name
      # answers the honest empty SignCard payload.
      def char_card(args)
        query = string_arg(args, "query") or
          raise InvalidArguments, "nabu_char needs a query (a glyph, sign name/value, " \
                                  "list number, or Gardiner-style code)"
        input = Nabu::Normalize.nfc(query.strip)
        case Nabu::CharDispatch.lane(input)
        when :cuneiform then cuneiform_char_payload(input)
        when :hieroglyphic then hieroglyphic_char_payload(input)
        when :name then name_char_payload(input)
        else note(HAN_CHAR_NOTE)
        end
      end

      # -- the nabu_char lanes (P68-3) --------------------------------------

      def resolve_readings
        slot = resolve(@readings)
        slot == :auto ? Nabu::CdliSignReadings.load_default : slot
      end

      def resolve_hieroglyphs
        slot = resolve(@hieroglyphs)
        slot == :auto ? Nabu::Hieroglyphs.load_default : slot
      end

      def cuneiform_char_payload(input)
        list = resolve_sign_list or return note(NO_SIGN_LIST_NOTE)
        sign_card_json(sign_card_query(list).run(input))
      end

      def hieroglyphic_char_payload(input)
        signs = resolve_hieroglyphs or return note(NO_UNIKEMET_NOTE)
        result = Query::HieroCard.new(hieroglyphs: signs, catalog: resolve(@catalog)).run(input)
        json(char_envelope(Query::HieroCard.json_payload(result), "unikemet"))
      end

      def name_char_payload(input)
        if (list = resolve_sign_list)
          result = sign_card_query(list).run(input)
          return sign_card_json(result) if result.card || result.candidates.any?
        end
        if (signs = resolve_hieroglyphs) && input.match?(Query::HieroCard::CODE)
          hiero = Query::HieroCard.new(hieroglyphs: signs, catalog: resolve(@catalog)).run(input)
          return json(char_envelope(Query::HieroCard.json_payload(hiero), "unikemet")) if hiero.card
        end
        return note(NO_SIGN_LIST_NOTE) if resolve_sign_list.nil? && resolve_hieroglyphs.nil?

        empty = Query::SignCard.json_payload(Query::SignCard::Result.new(input: input, card: nil, candidates: []))
        json(char_envelope(empty, resolve_sign_list ? "osl" : "unikemet"))
      end

      # The cuneiform card under the reference envelope; a card whose
      # Wiktionary senses joined also attributes that shelf.
      def sign_card_json(result)
        extra = []
        if result.card && !result.card.senses.empty?
          shelf = dictionary_shelf_envelope(Query::SignCard::WIKTIONARY_SLUG)
          extra << shelf.merge("role" => "senses") if shelf
        end
        json(char_envelope(Query::SignCard.json_payload(result), "osl", extra: extra))
      end

      # The reference envelope on a frozen char contract (string keys, the
      # contract's own style): the answering spine's source/license_class/
      # license top-level — additive keys only — and `attribution`, every
      # contributing dataset (the spine first).
      def char_envelope(payload, slug, extra: [])
        spine = reference_strings(slug) or return payload
        payload.merge("source" => spine["source"], "license_class" => spine["license_class"],
                      "license" => spine["license"],
                      "attribution" => [spine.merge("role" => CHAR_SPINE_ROLES.fetch(slug))] + extra)
      end

      # Envelope.reference with the string keys the frozen sign contracts use.
      # Split note: also read by nabu_signs (tools/signs.rb); kept with its primary user.
      def reference_strings(slug)
        Envelope.reference(slug)&.transform_keys(&:to_s)
      end

      # A catalog dictionary shelf's source envelope (slug, class, verbatim
      # license string), or nil when the shelf is not held.
      def dictionary_shelf_envelope(dictionary_slug)
        catalog = resolve(@catalog)
        return nil unless catalog&.table_exists?(:dictionaries)

        row = catalog[:dictionaries].join(:sources, id: Sequel[:dictionaries][:source_id])
                                    .where(Sequel[:dictionaries][:slug] => dictionary_slug)
                                    .select(Sequel[:sources][:slug], Sequel[:sources][:license_class],
                                            Sequel[:sources][:license]).first
        row && { "source" => row[:slug], "license_class" => row[:license_class], "license" => row[:license] }
      end

      def sign_card_query(list)
        Query::SignCard.new(sign_list: list, readings: resolve_readings,
                            fulltext: resolve(@fulltext), catalog: resolve(@catalog))
      end
    end
  end
end
