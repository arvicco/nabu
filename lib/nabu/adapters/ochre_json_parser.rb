# frozen_string_literal: true

module Nabu
  module Adapters
    # The `ochre-json` parser family (P55-2): shape normalizers for the JSON
    # the OCHRE platform (U. Chicago; pi.lib.uchicago.edu resolver) serves.
    # First registrant: rsti (the Ras Shamra Tablet Inventory).
    #
    # OCHRE's JSON is a mechanical transliteration of its XML, and two
    # quirks are therefore SYSTEMIC, not local:
    #
    # - singular/plural instability — any repeatable element serializes as a
    #   dict when it occurs once and a list when it repeats, recursively
    #   (properties.property.property is a dict on one item, a list on the
    #   next). #wrap is the one normalizer; call it before every iteration.
    # - content-shape instability — a text node serializes as a bare scalar,
    #   OR a {languages, string, lang} dict, OR a {content: …} wrapper
    #   (recursively), OR a list of any of these; an ABSENT value is often
    #   an empty dict {}, never null. #contents_of / #content_of extract the
    #   scalar(s); {} honestly yields nothing.
    #
    # Text items additionally carry `sections`: up to four parallel
    # renderings (transliteration / phonemic / graphemic / translation),
    # each per-surface (Recto/Verso/edges) → per-line. #sections normalizes
    # that tree; graphemic line values ship Ugaritic cuneiform as LITERAL
    # HTML-entity strings ("&#x10384;") which #decode_entities /
    # #graphemic_of turn into real U+10380-block codepoints.
    #
    # Stateless — every method is a module function over parsed JSON.
    class OchreJsonParser
      # "&#x10384;" (hex) or "&#66436;" (decimal) — the literal entity
      # strings the graphemic rendering ships.
      ENTITY = /&#(x\h+|\d+);/

      class << self
        # The singular/plural normalizer: nil → [], list → itself (same
        # object, cheap), anything else → a one-element list.
        def wrap(value)
          case value
          when nil then []
          when Array then value
          else [value]
          end
        end

        # Every scalar string reachable under +value+ through the witnessed
        # content shapes (class note). An empty dict — OCHRE's "absent" —
        # yields []. Non-string scalars (integer line labels) stringify.
        def contents_of(value)
          case value
          when nil then []
          when Array then value.flat_map { |element| contents_of(element) }
          when Hash
            return [value.fetch("string").to_s] if value.key?("string")
            return contents_of(value["content"]) if value.key?("content")

            []
          else [value.to_s]
          end
        end

        # The first scalar under +value+, or nil when there is none ({}).
        def content_of(value)
          contents_of(value).first
        end

        # A uuid field, or nil for every witnessed absence shape: the XML
        # self-closing form arrives as {} (Season 17's associated_uuid,
        # first real sync 2026-07-31 — the crash the fixtures now pin), a
        # wrapped dict carries its uuid string, an empty string is absence.
        def uuid_of(value)
          return (value.empty? ? nil : value) if value.is_a?(String)
          return nil unless value.is_a?(Hash)

          inner = value["uuid"]
          inner.is_a?(String) && !inner.empty? ? inner : nil
        end

        # Literal "&#x10384;"/"&#66436;" entity strings → real codepoints;
        # anything that is not an entity rides through verbatim.
        def decode_entities(string)
          string.gsub(ENTITY) do
            code = Regexp.last_match(1)
            codepoint = code.start_with?("x") ? code.delete_prefix("x").to_i(16) : code.to_i
            [codepoint].pack("U")
          end
        end

        # The renderings tree of one text item, normalized:
        #
        #   { "transliteration" => [
        #       { "surface" => "Recto",
        #         "lines" => [{ "label" => "1", "value" => <raw line value>,
        #                       "type" => "line", "divisions" => [],
        #                       "condition" => nil }, …] }, …
        #     ], … }
        #
        # "lines" are the LEAVES in document order, each with OCHRE's own
        # node type ("line", "separator", "region", or a childless
        # "column"/"section" header) and its qualities.condition
        # (missingLines, separatorStyle, damage …) — classifying furniture
        # is the adapter's call, the parser only normalizes. A container
        # nested under a surface (Column 1 under Recto; a joined fragment's
        # own section) rides each leaf's "divisions" as {label, type};
        # leaves sitting at the rendering ROOT (no surface node at all)
        # group under "surface" => nil.
        #
        # A rendering with no content (RS 1.001's translation is {}) maps to
        # [] — honestly present, honestly empty; a text item whose sections
        # is {} (the shell shape) yields {} outright. Line values stay RAW
        # (scalar for transliteration/phonemic, the
        # {supplementary, content} dict for graphemic — see #graphemic_of).
        def sections(text_item)
          (text_item["sections"] || {}).each_with_object({}) do |(rendering, node), renderings|
            renderings[rendering] = surfaces_of(node)
          end
        end

        # One graphemic line value → { "signs" => decoded codepoint string,
        # "marks" => the parallel damage-mark strings (only when upstream
        # ships them — Verso 22 carries supplementary only) }. A scalar
        # value (defensive) decodes into "signs" alone.
        def graphemic_of(value)
          case value
          when Hash
            signs = wrap(value["supplementary"]).map { |entity| decode_entities(entity.to_s) }.join
            graphemic = { "signs" => signs }
            graphemic["marks"] = wrap(value["content"]).map(&:to_s) if value.key?("content")
            graphemic
          else
            { "signs" => decode_entities(value.to_s) }
          end
        end

        private

        # One rendering's top-level nodes → surfaces. A node that holds
        # children is a surface (Recto, a "Column N" at the root); a run of
        # childless nodes at the root (lines with no surface at all — RS
        # 15.125) groups under a nil surface.
        def surfaces_of(node)
          wrap(node.is_a?(Hash) ? node["section"] : node).each_with_object([]) do |top, surfaces|
            if top.key?("section")
              surfaces << { "surface" => label_of(top), "lines" => leaves_of(top, []) }
            else
              surfaces << { "surface" => nil, "lines" => [] } unless surfaces.last && surfaces.last["surface"].nil?
              surfaces.last["lines"] << leaf_of(top, [])
            end
          end
        end

        # Every leaf under +container+, depth-first in document order;
        # nested containers (a Column under Recto, a joined fragment's own
        # section) accumulate into each leaf's "divisions".
        def leaves_of(container, divisions)
          wrap(container["section"]).flat_map do |node|
            next [leaf_of(node, divisions)] unless node.key?("section")

            leaves_of(node, divisions + [{ "label" => label_of(node), "type" => node["type"] }])
          end
        end

        def leaf_of(node, divisions)
          { "label" => label_of(node), "value" => node["value"], "type" => node["type"],
            "divisions" => divisions, "condition" => node.dig("qualities", "condition") }
        end

        def label_of(node)
          content_of(node.dig("identification", "label"))
        end
      end
    end
  end
end
