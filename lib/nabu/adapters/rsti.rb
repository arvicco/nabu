# frozen_string_literal: true

require "json"

require_relative "ochre_json_parser"
require_relative "../ochre_fetch"

module Nabu
  module Adapters
    # RSTI — the Ras Shamra Tablet Inventory (P55-2): the U. Chicago
    # CORPUS/OCHRE inventory of every inscribed object from Ugarit (Ras
    # Shamra) and Ras Ibn Hani, served by the pi.lib.uchicago.edu resolver
    # (Nabu::OchreFetch; new `ochre-json` family).
    #
    # == The verdict that shapes everything: inventory-first, text exceptional
    #
    # The corpus is ~5,000-7,000 rich inventory records (RS/RIH number,
    # museum number, French TEO findspot, script/language, size, the
    # KTU/CTA/UT/RSO concordance) across 35 season/collection sets. The
    # text-side record behind a set entry is usually UNPUBLISHED — the API
    # answers `{"result":[]}` with HTTP 200 (8 of 10 scout probes;
    # persisted as a tombstone) or a shell whose sections are {} — so ~99%
    # of documents are honest ZERO-passage metadata records ("text_layer"
    # => "none", the ebl precedent). Where a full edition exists (RS 1.001,
    # the one witnessed), it carries four parallel renderings:
    # transliteration (the passage text, line grain per surface), phonemic,
    # graphemic (Ugaritic cuneiform as literal "&#x103xx;" entities,
    # decoded to real U+10380-block codepoints), translation.
    #
    # == Identity
    #
    # Document = the inventory record (spatialUnit) = the RS/RIH number.
    # urn_for is the ONE minting rule: NFC, strip, lowercase, whitespace
    # runs → "-", every other character (. + / [ ] ,) verbatim — minimal
    # transformation (the ebl precedent), collision-safe (brackets and join
    # marks stay distinct: rs-74.[001] can never collide with a plain
    # rs-74.001). Passage = <doc>:<surface-slug>.<line> (recto.1,
    # lower-edge.18). A record re-listed by an aggregate set ("Season
    # 1-11") is first-wins, censused via discovery_skips.
    #
    # == The line model: FURNITURE creates no passage
    #
    # OCHRE types every leaf under a rendering (OchreJsonParser#sections
    # keeps the type, its condition qualities and any nested container
    # path). Only a "line" with a string value is text. The rest is
    # furniture (censused live 2026-11-13 over the 217 resolving text
    # items: 3,443 text lines beside 219 rulings, 131 lacunae, 7 bare
    # headers, 4 empty rows), classified and never minted:
    #
    #   separator                  a scribal ruling → state "single ruling"
    #   region / a line carrying   a lacuna → state "N lines missing" when
    #     condition.missingLines     counted, else upstream's own label
    #                                ("broken", "missing"), else "broken"
    #   a childless column/section a header ("Column 4", "Vacat?") → state
    #                                with its label
    #   a line with no value       an empty row → counted only
    #
    # States ride the ATF precedent: "states" on the NEXT minted line,
    # trailing ones as "states_after" on the last; the per-kind census is
    # metadata "line_furniture". An edition is a text item with at least
    # one text line (furniture-only items are shells). Nested containers
    # (Column 1 under Recto; a joined fragment's own section under each
    # surface) extend the passage urn (recto.rih-78/21.01') and ride
    # "column"/"division"; lines at the rendering ROOT mint <doc>:<line>.
    # A line whose value is not a string quarantines the document
    # (MIXED_MARKUP); an unseen leaf type loud-stops.
    #
    # == License (granted)
    #
    # CC BY-NC-SA 4.0 — the API's own availability.license on season sets
    # and text items, confirmed by grant by email (Miller Prosser, U. Chicago
    # CORPUS/OCHRE, 2026-07-27): "retrieve the RSTI data and add it to your
    # collection, with attribution. The data is governed by the NC-SA
    # license." Class nc, never redistributed like all nc; the attribution rides
    # the manifest credit seam onto every serving surface.
    class Rsti < Nabu::Adapter
      MENU_UUID = "4a7c67a2-6814-4e88-b24c-04db5ab2ad2a"
      URN_PREFIX = "urn:nabu:rsti:"

      # The menu-level availability credit, verbatim (fixture menu.json).
      TEO_CREDIT = "All inscribed object information derived from Bordreuil and Pardee (1989) " \
                   "La Trouvaille Épigraphique de l'Ougarit 1: Concordance. Ras Shamra-Ougarit 5, " \
                   "Éditions Recherche sur les Civilisations: Paris, with additions and " \
                   "corrections. Text editions are attributed to the editors. Photos are " \
                   "copyright of PhoTEO, MRS."

      MANIFEST = Nabu::SourceManifest.new(
        id: "rsti",
        name: "RSTI — Ras Shamra Tablet Inventory (U. Chicago CORPUS/OCHRE; the inscribed " \
              "objects of Ugarit and Ras Ibn Hani)",
        license: "CC BY-NC-SA 4.0 — the API's own availability.license on season sets and text " \
                 "items (\"Creative Commons Attribution-NonCommercial-ShareAlike\", " \
                 "creativecommons.org/licenses/by-nc-sa/4.0/), confirmed by grant by email (Miller " \
                 "Prosser, U. Chicago CORPUS/OCHRE, 2026-07-27, verbatim: \"retrieve the RSTI " \
                 "data and add it to your collection, with attribution. The data is governed by " \
                 "the NC-SA license.\"). Menu-level availability verbatim: \"#{TEO_CREDIT}\"",
        license_class: "nc",
        upstream_url: "https://ochre.lib.uchicago.edu/RSTI/",
        parser_family: "ochre-json",
        credit: "Ras Shamra Tablet Inventory (M. Prosser, D. Pardee et al.), U. Chicago " \
                "CORPUS/OCHRE; inscribed-object data after Bordreuil & Pardee (1989), La " \
                "Trouvaille Épigraphique de l'Ougarit 1 (Ras Shamra-Ougarit 5)"
      )

      # RSTI language names → stored codes, the witnessed vocabulary
      # (censused over the five scouted season sets, 2026-07-31: Ugaritic
      # 559 · Akkadian 272 · absent 121 · Hurrian 84 · Egyptian 11 · Latin
      # 5 · Cypro-Minoan 3 · Sumerian 2 · Hittite 1 · Phoenician 1 + 11
      # multi-language lists). Cypro-Minoan is undeciphered — no ISO 639
      # code exists, so `und` is the honest tag. An UNSEEN name loud-stops
      # (ParseError quarantines the document; extend deliberately).
      LANGUAGE_CODES = {
        "Ugaritic" => "uga", "Akkadian" => "akk", "Hurrian" => "xhu", "Sumerian" => "sux",
        "Egyptian" => "egy", "Hittite" => "hit", "Latin" => "lat", "Phoenician" => "phn",
        "Cypro-Minoan" => "und"
      }.freeze

      # No Language property at all (121 of 1,070 sampled records): und,
      # never a guess.
      UNKNOWN_LANGUAGE = "und"

      # OCHRE's explicit empty: a property value "<unassigned>" (one fixed
      # vocabulary uuid, c4e4fd83-…) — witnessed live on Language (RS 8.220
      # and four more, which loud-stopped as an unknown language) and on
      # Object type. It is absence, filtered at property flattening: the
      # no-Language rule (und) applies, no metadata key carries it.
      UNASSIGNED = "<unassigned>"

      # The resolver's other empty answer: a &format=json request answered
      # by a bare XML declaration and nothing else (38 bytes, persisted
      # verbatim by the fetch; RIH 83/02 and one more live). No record —
      # the "empty-answer" metadata-only status, never a JSON error.
      EMPTY_ANSWER = /\A<\?xml[^>]*\?>\z/

      # A parallel-rendering value that is a pure content wrapper (vs mixed
      # markup — MIXED_MARKUP).
      PURE_CONTENT_KEYS = %w[content string lang languages].freeze

      # The quarantine reason for a transliteration line whose value is not
      # a string (81 lines in 7 live text items, RS 17.238's 19 among
      # them): OCHRE's XML interleaves italic syllables, superscript
      # determinatives and plain logograms inside one line, and its JSON
      # transliteration flattens them into parallel lists ({"i" => [...],
      # "content" => [...], "sup" => ...}) — the interleaving order is
      # GONE. The XML rendition would keep it, but it is outside this
      # adapter's delivery (OchreFetch fetches &format=json only; the only
      # XML ever on disk is the empty-answer prologue), so the document
      # quarantines rather than serve a reordered or printed-Hash reading.
      MIXED_MARKUP = "OCHRE's JSON flattens this line's interleaved markup (i/sup/content " \
                     "lists) and the piece order is unrecoverable; the XML rendition is outside " \
                     "the json-only delivery"

      # Inventory-record properties carried into document metadata, by
      # their upstream label (single-valued; Language is handled apart).
      PROPERTY_KEYS = {
        "Object type" => "object_type", "Museum Number" => "museum_number",
        "Full TEO Findspot" => "findspot", "Script" => "script", "Size" => "size"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # The ONE minting rule (class note).
      def self.urn_for(label)
        "#{URN_PREFIX}#{slug(label)}"
      end

      # NFC, strip, lowercase, whitespace runs → "-", the rest verbatim.
      # Shared by document labels and surface labels ("Lower edge" →
      # lower-edge).
      def self.slug(label)
        Normalize.nfc(label.to_s.strip).downcase.gsub(/[[:space:]]+/, "-")
      end

      # RSTI language name → stored code; unseen names loud-stop (class
      # note on LANGUAGE_CODES).
      def self.language_code!(name, context:)
        LANGUAGE_CODES.fetch(name) do
          raise ParseError, "#{context}: unknown RSTI language #{name.inspect} — the witnessed " \
                            "vocabulary is #{LANGUAGE_CODES.keys.join(', ')}; extend " \
                            "Rsti::LANGUAGE_CODES deliberately, never silently"
        end
      end

      # The document language from the record's language NAMES: none → und;
      # several (bilingual tablets) → the first listed governs, the full
      # list rides metadata "languages".
      def self.document_language(names, context:)
        return UNKNOWN_LANGUAGE if names.empty?

        language_code!(names.first, context: context)
      end

      # HEAD the menu resolver: reachability + Last-Modified drift against
      # the .ochre-fetch.json pin. metadata_url nil — the license lives
      # inside the fetched JSON itself (availability.license).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "menu #{MENU_UUID}", zip_url: Nabu::OchreFetch.item_url(MENU_UUID),
          metadata_url: nil, state_subdir: "", state_file: Nabu::OchreFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::OchreFetch::DELAY)
        super()
        @delay = delay
        @index_cache = {}
        @set_cache = {}
      end

      # One ref per inventory record across every set file, sorted by urn;
      # a urn re-listed by a later set file is first-wins (class note). A
      # pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        index(workdir)[:refs].each(&block)
      end

      def discovery_skips(workdir)
        DiscoverySkips.new(skipped_by_rule: index(workdir)[:duplicates])
      end

      def parse(document_ref)
        record = record_for(document_ref)
        label = OchreJsonParser.content_of(record.dig("identification", "label")).to_s
        urn = self.class.urn_for(label)
        text_uuid = OchreJsonParser.uuid_of(record["associated_uuid"])
        text_item, status = text_item_for(document_ref, text_uuid)
        build_document(document_ref, urn: urn, label: label, record: record,
                                     text_item: text_item, status: status, text_uuid: text_uuid)
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # Two-stage OchreFetch (menu + sets refreshed, text details
      # accumulated resumably — retention posture in the OchreFetch class
      # note). +force+ has no destructive surface (nothing is ever
      # deleted), so it is accepted for interface parity and ignored.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::OchreFetch.sync!(menu_uuid: MENU_UUID, dir: workdir,
                                        delay: @delay, progress: progress)
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::OchreFetch::Error => e
        raise Nabu::FetchError, "rsti fetch failed into #{workdir}: #{e.message}"
      end

      private

      def fetch_notes(result)
        notes = "#{result.sets} sets; #{result.texts_fetched} text details fetched, " \
                "#{result.texts_cached} already present"
        notes += "; #{result.missing.size} set-promised uuid(s) 404 (censused)" unless result.missing.empty?
        notes
      end

      # -- discovery index ------------------------------------------------------

      def index(workdir)
        @index_cache[File.expand_path(workdir)] ||= build_index(workdir)
      end

      def build_index(workdir)
        refs = {}
        duplicates = 0
        Dir.glob(File.join(workdir, Nabu::OchreFetch::SETS_DIRNAME, "*.json")).each do |path|
          records_of(path).each_with_index do |record, position|
            label = OchreJsonParser.content_of(record.dig("identification", "label"))
            next if label.nil?

            urn = self.class.urn_for(label)
            if refs.key?(urn)
              duplicates += 1 # first set file wins, the house rule
            else
              refs[urn] = Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: path,
                                                metadata: { "index" => position })
            end
          end
        end
        { refs: refs.values.sort_by!(&:id), duplicates: duplicates }
      end

      def parsed_set(path)
        @set_cache[path] ||= JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: set file is not valid JSON: #{e.message}"
      end

      def records_of(path)
        OchreJsonParser.wrap(parsed_set(path).dig("ochre", "set", "items", "spatialUnit"))
      end

      def record_for(document_ref)
        records_of(document_ref.path).fetch(document_ref.metadata.fetch("index"))
      end

      # The text-side record behind +text_uuid+ → [item-or-nil, status]:
      # "no-text" (no associated text exists upstream — the absent key or
      # the {} self-closing form; a resync must not chase it),
      # "unfetched" (a real uuid whose file is not on disk), "unpublished" (the
      # {"result":[]} tombstone), "shell" (resolves, no transliteration
      # lines), "edition".
      def text_item_for(document_ref, text_uuid)
        return [nil, "no-text"] if text_uuid.nil?

        workdir = File.dirname(document_ref.path, 2)
        path = File.join(workdir, Nabu::OchreFetch::TEXTS_DIRNAME, "#{text_uuid}.json")
        return [nil, "unfetched"] unless File.file?(path)

        body = File.read(path)
        return [nil, "empty-answer"] if body.strip.match?(EMPTY_ANSWER)

        item = JSON.parse(body).dig("ochre", "text")
        return [nil, "unpublished"] if item.nil? # the {"result":[]} tombstone

        [item, text_lines(item, context: "#{path}: #{document_ref.id}").any? ? "edition" : "shell"]
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: text detail is not valid JSON: #{e.message}"
      end

      # -- the line model -------------------------------------------------------

      # The transliteration leaves classified (class note on FURNITURE):
      # [{ "kind" => :text | :ruling | :lacuna | :header | :empty,
      #    "leaf" => <parser leaf>, "surface" => label-or-nil }, …] in
      # document order. A mixed-markup line raises (MIXED_MARKUP note).
      def classified_leaves(text_item, context:)
        (OchreJsonParser.sections(text_item)["transliteration"] || []).flat_map do |surface|
          surface["lines"].map do |leaf|
            { "kind" => leaf_kind(leaf, surface: surface["surface"], context: context),
              "leaf" => leaf, "surface" => surface["surface"] }
          end
        end
      end

      def text_lines(text_item, context:)
        classified_leaves(text_item, context: context).select { |entry| entry["kind"] == :text }
      end

      def leaf_kind(leaf, surface:, context:)
        case leaf["type"]
        when "line" then line_kind(leaf, surface: surface, context: context)
        when "separator" then :ruling
        when "region" then :lacuna
        when "column", "section" then :header
        else
          raise ParseError, "#{context}: unknown OCHRE leaf type #{leaf['type'].inspect} " \
                            "(witnessed: line, separator, region, column, section) — extend " \
                            "Rsti#leaf_kind deliberately, never silently"
        end
      end

      def line_kind(leaf, surface:, context:)
        value = leaf["value"]
        return :lacuna if leaf["condition"].is_a?(Hash) && leaf["condition"].key?("missingLines")
        return :empty if value.nil? || (value.is_a?(String) && value.strip.empty?)
        return :text if value.is_a?(String) || value.is_a?(Integer)

        where = [surface, *leaf["divisions"].map { |d| d["label"] }, leaf["label"]].compact.join(" ")
        raise ParseError, "#{context}: #{MIXED_MARKUP} — mixed-markup line #{where} " \
                          "(value keys #{value.is_a?(Hash) ? value.keys.join('/') : value.class})"
      end

      # The verbatim-ish state string a furniture leaf contributes.
      def state_of(entry)
        leaf = entry["leaf"]
        condition = leaf["condition"].is_a?(Hash) ? leaf["condition"] : {}
        case entry["kind"]
        when :ruling then [condition["separatorStyle"], "ruling"].compact.join(" ")
        when :lacuna then lacuna_state(leaf["label"], condition["missingLines"])
        when :header then leaf["label"]
        end
      end

      # A counted lacuna names its extent; otherwise upstream's own label
      # ("broken", "missing") when it is not a line number; else "broken"
      # (missingLines -1 is OCHRE's "extent unknown").
      def lacuna_state(label, missing)
        return "#{missing} line#{'s' unless missing == 1} missing" if missing.is_a?(Integer) && missing.positive?
        return label if label.is_a?(String) && !label.strip.empty? && !label.match?(/\A\d/)

        "broken"
      end

      # -- document assembly ----------------------------------------------------

      def build_document(document_ref, urn:, label:, record:, text_item:, status:, text_uuid:)
        properties = flatten_properties(record["properties"])
        language_names = property_values(properties, "Language")
        language = document_language(text_item, language_names, label: label)
        metadata = record_metadata(label: label, record: record, properties: properties,
                                   language_names: language_names, text_item: text_item,
                                   status: status, text_uuid: text_uuid,
                                   set_label: season_label_of(document_ref))
        # The honest metadata-only marker (the ebl/local-library precedent):
        # anything short of an edition catalogues with zero passages. An
        # edition always yields lines (text_item_for's status rule).
        metadata["text_layer"] = "none" unless status == "edition"
        lines = status == "edition" ? line_plan(text_item, urn: urn, metadata: metadata) : []
        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: document_ref.path,
          title: title_of(record, label), metadata: metadata
        )
        append_passages(document, lines, language: language)
        document
      end

      # The text item's own language field governs when present; else the
      # inventory record's Language property; else und.
      def document_language(text_item, language_names, label:)
        name = text_item && OchreJsonParser.content_of(text_item["language"])
        return self.class.language_code!(name, context: label) if name

        self.class.document_language(language_names, context: label)
      end

      def title_of(record, label)
        OchreJsonParser.content_of(record["associated_desc"]) || label
      end

      def record_metadata(label:, record:, properties:, language_names:, text_item:, status:, text_uuid:, set_label:)
        metadata = { "rs_label" => label, "text_status" => status }
        metadata["text_uuid"] = text_uuid if text_uuid
        metadata["set"] = set_label if set_label
        copy_record_fields(metadata, record)
        copy_properties(metadata, properties, language_names)
        copy_text_fields(metadata, text_item)
        concordances = concordances_of(record, text_item)
        metadata["concordances"] = concordances unless concordances.empty?
        metadata.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end

      def copy_record_fields(metadata, record)
        description = OchreJsonParser.content_of(record["description"])
        metadata["description"] = description if description
        aliases = OchreJsonParser.contents_of(record.dig("identification", "alias"))
        metadata["aliases"] = aliases unless aliases.empty?
      end

      def copy_properties(metadata, properties, language_names)
        PROPERTY_KEYS.each do |upstream, key|
          values = property_values(properties, upstream)
          metadata[key] = values.join(", ") unless values.empty?
        end
        metadata["languages"] = language_names unless language_names.empty?
      end

      def copy_text_fields(metadata, text_item)
        return if text_item.nil?

        genre = property_values(flatten_properties(text_item["properties"]), "Genre").first
        metadata["genre"] = genre if genre
        type = OchreJsonParser.content_of(text_item["type"])
        metadata["text_type"] = type if type
      end

      # The KTU/CTA/UT/RSO interop keys: the record's associated_alias
      # ("(CTA 34, KTU 1.39, RSO XII 1, UT 1)") merged with the text item's
      # own alias list.
      def concordances_of(record, text_item)
        from_alias = OchreJsonParser.content_of(record["associated_alias"]).to_s
                                    .delete_prefix("(").delete_suffix(")")
                                    .split(", ").map(&:strip).reject(&:empty?)
        from_text = text_item ? OchreJsonParser.contents_of(text_item.dig("identification", "alias")) : []
        (from_alias + from_text).uniq
      end

      # OCHRE properties nest recursively (Classification → Textual feature
      # → Script/Language); flatten to [label, values] pairs at every depth.
      def flatten_properties(node)
        OchreJsonParser.wrap(node.is_a?(Hash) ? node["property"] : node).flat_map do |property|
          pair = [OchreJsonParser.content_of(property["label"]),
                  OchreJsonParser.contents_of(property["value"]) - [UNASSIGNED]]
          [pair] + flatten_properties(property)
        end
      end

      def property_values(properties, label)
        properties.select { |name, _values| name == label }.flat_map { |_name, values| values }
      end

      # -- passages -------------------------------------------------------------

      # Text leaves become passages; furniture becomes the NEXT passage's
      # "states" (trailing furniture: the last passage's "states_after") and
      # the document's "line_furniture" census — the ATF state-line
      # precedent. Empty rows and headers count but carry no state text
      # beyond a header's own label.
      # The text leaves as [entry, annotations] pairs; the furniture
      # census lands in +metadata+ (still mutable — the document is not
      # built yet).
      def line_plan(text_item, urn:, metadata:)
        renderings = OchreJsonParser.sections(text_item)
        parallels = %w[phonemic graphemic translation].to_h { |name| [name, lines_by_key(renderings[name])] }
        furniture = Hash.new(0)
        omitted = Hash.new(0)
        lines = []
        pending = []
        classified_leaves(text_item, context: urn).each do |entry|
          if entry["kind"] == :text
            lines << [entry, line_annotations(entry, parallels: parallels, states: pending, omitted: omitted)]
            pending = []
          else
            furniture[entry["kind"].to_s] += 1
            state = state_of(entry)
            pending << Normalize.nfc(state) if state
          end
        end
        lines.last[1]["states_after"] = pending unless pending.empty?
        metadata["line_furniture"] = furniture.to_a.to_h unless furniture.empty?
        metadata["mixed_markup_parallels_omitted"] = omitted["count"] if omitted["count"].positive?
        lines
      end

      def append_passages(document, lines, language:)
        lines.each_with_index do |(entry, annotations), sequence|
          document << Nabu::Passage.new(urn: passage_urn(document.urn, entry["surface"], entry["leaf"]),
                                        language: language, text: Normalize.nfc(entry["leaf"]["value"].to_s),
                                        annotations: annotations, sequence: sequence)
        end
      end

      def line_annotations(entry, parallels:, states:, omitted:)
        leaf = entry["leaf"]
        key = leaf_key(entry["surface"], leaf)
        annotations = {}
        annotations["surface"] = entry["surface"] if entry["surface"]
        division_annotations(annotations, leaf["divisions"])
        annotations["line"] = leaf["label"]
        annotations["states"] = states unless states.empty?
        %w[phonemic translation].each do |name|
          value = parallels[name][key]
          next omitted["count"] += 1 if mixed_markup?(value)

          annotate_scalar(annotations, name, value)
        end
        annotate_graphemic(annotations, parallels["graphemic"][key])
        annotations
      end

      # <doc>:<surface>.<division…>.<line> — a root-level line has no
      # surface segment (<doc>:<line>). An unlabeled TEXT line cannot mint.
      def passage_urn(document_urn, surface, leaf)
        label = leaf["label"]
        raise ParseError, "#{document_urn}: transliteration text line without a label" if label.to_s.strip.empty?

        segments = [surface, *leaf["divisions"].map { |d| d["label"] }].compact.map { |s| self.class.slug(s) }
        "#{document_urn}:#{(segments + [label]).join('.')}"
      end

      # Nested containers: a Column rides "column", anything else (a joined
      # fragment's own section) "division"; several join with " / ".
      def division_annotations(annotations, divisions)
        divisions.group_by { |d| d["type"] == "column" ? "column" : "division" }.each do |key, group|
          annotations[key] = group.map { |d| d["label"] }.compact.join(" / ")
        end
      end

      def leaf_key(surface, leaf)
        [surface, leaf["divisions"].map { |d| d["label"] }, leaf["label"]]
      end

      # A parallel rendering's MIXED-markup value (i/sup/b … beside
      # content — order unrecoverable, MIXED_MARKUP note) is omitted, never
      # a partial reading; the caller counts the omission.
      def mixed_markup?(value)
        value.is_a?(Hash) && !(value.keys - PURE_CONTENT_KEYS).empty?
      end

      # A plain string, or a pure content wrapper ({content}/{string}) →
      # its scalar.
      def annotate_scalar(annotations, key, value)
        scalar = value.is_a?(String) ? value : OchreJsonParser.content_of(value)
        annotations[key] = Normalize.nfc(scalar) if scalar
      end

      def annotate_graphemic(annotations, value)
        return if value.nil?

        graphemic = OchreJsonParser.graphemic_of(value)
        annotations["graphemic"] = Normalize.nfc(graphemic["signs"]) unless graphemic["signs"].empty?
        annotations["graphemic_marks"] = graphemic["marks"] if graphemic.key?("marks")
      end

      # (surface label, line label) → raw line value, for the non-spine
      # renderings.
      def lines_by_key(surfaces)
        (surfaces || []).each_with_object({}) do |surface, lines|
          surface["lines"].each do |leaf|
            next unless leaf["type"] == "line"

            lines[leaf_key(surface["surface"], leaf)] = leaf["value"]
          end
        end
      end

      # The owning set's own label ("TEO Season 01") — records do not carry
      # their set, but the ref's path IS the set file (cached parse).
      def season_label_of(document_ref)
        OchreJsonParser.content_of(parsed_set(document_ref.path).dig("ochre", "set", "identification", "label"))
      end
    end
  end
end
