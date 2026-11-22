# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_signs tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      SIGNS_DESCRIPTION =
        "The cuneiform sign desk (P53-2): ATF transliteration resolved token by token through " \
        "the local Oracc Sign List into sign identities — value → sign name → Unicode " \
        "codepoint(s). Give EXACTLY ONE of: `urn` — a passage or document urn from the ATF " \
        "corpora (cdli/oracc/ebl/etcsl; e.g. urn:nabu:cdli:p469841 — language read from the " \
        "row, the catalog opened read-only) — or `text` — raw ATF transliteration (`lang` " \
        "optional). C-ATF ASCII folds apply (sz→š, s,→ṣ, t,→ṭ, u2→u₂); `dialect: \"etcsl\"` " \
        "adds the ETCSL romanization (c→š, j→ŋ), auto-selected for etcsl urns. Every token " \
        "carries ONE honest status: deterministic · qualified (valueₓ(SIGN), the explicit sign " \
        "resolved) · ambiguous (ALL candidate signs listed, never one silently) · no-codepoint " \
        "(sign resolved, honestly unencoded upstream) · broken (x, [...]) · unknown (not in " \
        "the OSL — said plainly). Determinatives are unbraced and flagged. The sign list adds " \
        "IDENTITY, not curriculum. Bounded (default #{SIGNS_DEFAULT_MAX_LINES} lines, max " \
        "#{SIGNS_MAX_LINES_CAP}); the restricted-exclusion stance applies to urn mode. `sign_list` " \
        "carries the OSL license envelope; urn mode also carries the text's license_class.".freeze

      SIGNS_SCHEMA = {
        type: "object",
        properties: {
          urn: { type: "string",
                 description: "A passage or document urn out of the ATF corpora " \
                              "(urn:nabu:cdli:p469841, urn:nabu:oracc:…). Exactly one of " \
                              "urn/text." },
          text: { type: "string",
                  description: "Raw ATF transliteration text (one or more lines). Exactly one " \
                               "of urn/text." },
          lang: { type: "string",
                  description: "Language filter for %lang-qualified sign readings (sux, akk, " \
                               "…); urn mode defaults to the passage's language." },
          dialect: { type: "string", enum: ["etcsl"],
                     description: "Transliteration dialect fold: etcsl (c→š, j→ŋ). Auto for " \
                                  "etcsl urns; default C-ATF otherwise." },
          max_lines: { type: "integer", minimum: 1, maximum: SIGNS_MAX_LINES_CAP,
                       default: SIGNS_DEFAULT_MAX_LINES,
                       description: "Maximum transliteration lines resolved per response." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        additionalProperties: false
      }.freeze

      private

      def signs(args)
        urn = string_arg(args, "urn")
        text = string_arg(args, "text")
        raise InvalidArguments, "nabu_signs needs exactly one of urn or text" unless urn.nil? ^ text.nil?

        dialect = signs_dialect_arg(args)
        list = resolve_sign_list or return note(NO_SIGN_LIST_NOTE)
        bound = clamp(args["max_lines"], default: SIGNS_DEFAULT_MAX_LINES, max: SIGNS_MAX_LINES_CAP)
        result = urn ? signs_urn_result(urn, args, list, dialect) : signs_text_result(text, args, list, dialect)
        return result if result.is_a?(Hash) # a note/withheld response, already shaped

        json(signs_payload(result, bound))
      rescue Query::Signs::Error => e
        tool_error(e.message)
      end

      # -- nabu_signs helpers ------------------------------------------------------

      # Resolve the sign-list slot: :auto feature-detects canonical/osl per
      # call (SignList.load_default memoizes the parse per path), anything
      # else is the configured instance / nil.
      # Split note: also read by nabu_char (tools/char.rb); kept with its primary user.
      def resolve_sign_list
        slot = resolve(@sign_list)
        slot == :auto ? Nabu::SignList.load_default : slot
      end

      def signs_dialect_arg(args)
        dialect = string_arg(args, "dialect")
        return nil if dialect.nil?
        return dialect.to_sym if Nabu::AtfTokenizer::DIALECTS.map(&:to_s).include?(dialect)

        raise InvalidArguments, "dialect must be one of: #{Nabu::AtfTokenizer::DIALECTS.join(', ')}"
      end

      def signs_text_result(text, args, list, dialect)
        Query::Signs.new(sign_list: list)
                    .run_text(text, language: string_arg(args, "lang"), dialect: dialect || :catf)
      end

      def signs_urn_result(urn, args, list, dialect)
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        result = Query::Signs.new(sign_list: list, catalog: catalog)
                             .run_urn(urn, language: string_arg(args, "lang"), dialect: dialect)
        return urn_not_found(urn) if result.nil?
        return withheld(urn, result.license_class) if withhold?(result.license_class,
                                                                args["include_restricted"] == true)

        result
      end

      # The frozen contract (Query::Signs.json_payload — ONE serializer with
      # the CLI's --json), bounded per the MCP surface with an honest note.
      def signs_payload(result, bound)
        payload = signs_envelope(result, Query::Signs.json_payload(result))
        lines = payload.fetch("lines")
        return payload if lines.size <= bound

        payload.merge(
          "lines" => lines.take(bound),
          "note" => "#{lines.size} line(s) total, showing #{bound} — raise max_lines " \
                    "(max #{SIGNS_MAX_LINES_CAP}), or read line by line with passage urns"
        )
      end

      # The reference envelope on the sign desk (additive keys): the OSL's
      # license as `sign_list`, and — urn mode — the TEXT's effective
      # license_class beside the source slug the contract already carries.
      def signs_envelope(result, payload)
        sign_list = reference_strings("osl")
        payload = payload.merge("sign_list" => sign_list) if sign_list
        return payload unless result.respond_to?(:license_class) && result.license_class

        payload.merge("license_class" => result.license_class)
      end
    end
  end
end
