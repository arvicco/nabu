# frozen_string_literal: true

# Nabu::MCP::Tools — the nabu_show tool. A partial of
# lib/nabu/mcp/tools.rb, the registry that loads it.
module Nabu
  module MCP
    class Tools
      SHOW_DESCRIPTION =
        "Read the nabu corpus by urn: one passage, a whole document, an inclusive range, or " \
        "a parallel-aligned translation. urn shapes — passage: " \
        "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1 · document: " \
        "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2 · range: <document-urn>:1.1-1.10 " \
        "(inclusive slice) · papyrus: urn:nabu:ddbdp:aegyptus:89:240:b2:5 · treebank " \
        "sentence: urn:nabu:proiel:afnik:194690. A shortened CITATION PREFIX between document " \
        "and passage grain (…:avest020:Y.19.1 over passages Y.19.1.a/b) lists everything below " \
        "it, boundary-exact — term-less browsing needs no search hit first. `parallel: true` " \
        "aligns the same work's " \
        "`parallel_lang` (default eng) edition line by line. Passage lists are bounded by " \
        "max_passages (default #{SHOW_DEFAULT_MAX_PASSAGES}, cap #{SHOW_MAX_PASSAGES_CAP}) " \
        "with an honest truncation note. Every passage carries urn, language, and " \
        "license_class — preserve them when quoting. Withdrawn/retired items appear, flagged. " \
        "The owner's own notes on the urn ride along in `notes` (documents also count " \
        "passage-note children) — useful curatorial context. A metrically scanned passage " \
        "carries `meter` (code, foot pattern, producer); an epigraphic document whose " \
        "parse-captured Pleiades findspot id resolves through the local gazetteer dump " \
        "carries `findspot` (both keys absent otherwise — absence of the dump or of the " \
        "enrichment, not a claimed absence of fact). `segmented: true` adds a word-segmented " \
        "rendering of Tibetan (xct/bod/otb) passages as a present-only `segmented` key per " \
        "passage record; a not-applicable call carries `segmentation_note` instead. " \
        "`senses: true` adds each shown passage's token senses (DCS WordSem ids — the CLI's " \
        "show --senses): a present-only `senses` list per passage record plus a `sense_entries` " \
        "map resolving the ids against the sense shelf; a source with no ruled token senses " \
        "answers `senses_note` instead. The `findspot` block carries the gazetteer's " \
        "`attribution` (source, license, the place's upstream URI) — preserve it when quoting " \
        "the place facts.".freeze

      SHOW_SCHEMA = {
        type: "object",
        properties: {
          urn: { type: "string",
                 description: "Passage, document, or range urn (see the tool description " \
                              "for the shapes)." },
          parallel: { type: "boolean", default: false,
                      description: "Align with the same work's parallel_lang edition by " \
                                   "citation suffix." },
          parallel_lang: { type: "string", default: "eng",
                           description: "Language of the parallel edition (with parallel: true)." },
          max_passages: { type: "integer", minimum: 1, maximum: SHOW_MAX_PASSAGES_CAP,
                          default: SHOW_DEFAULT_MAX_PASSAGES,
                          description: "Bound on listed passages/rows; truncation is noted " \
                                       "honestly." },
          segmented: { type: "boolean", default: false,
                       description: "Add a word-segmented rendering of Tibetan (xct/bod/otb) " \
                                    "passages: each passage record gains a present-only " \
                                    "`segmented` key (text with spaces at word boundaries, " \
                                    "tokens verbatim); when not applicable, a top-level " \
                                    "`segmentation_note` says why." },
          senses: { type: "boolean", default: false,
                    description: "Add the token senses (DCS WordSem ids) of each shown passage " \
                                 "(the CLI's show --senses): a passage record gains a " \
                                 "present-only `senses` list — one row per citing token (form, " \
                                 "lemma, ids) — and the payload a `sense_entries` map id → " \
                                 "{headword, gloss} resolved against the sense shelf (an id the " \
                                 "shelf lacks is absent from the map). A source with no ruled " \
                                 "token senses answers a top-level `senses_note` instead." },
          include_restricted: INCLUDE_RESTRICTED_SCHEMA
        },
        required: ["urn"],
        additionalProperties: false
      }.freeze

      private

      def show(args)
        urn = string_arg(args, "urn") or raise InvalidArguments, "nabu_show needs a urn"
        catalog = resolve(@catalog) or return note(NO_CORPUS_NOTE)
        bound = clamp(args["max_passages"], default: SHOW_DEFAULT_MAX_PASSAGES, max: SHOW_MAX_PASSAGES_CAP)
        include_restricted = args["include_restricted"] == true
        return show_parallel(catalog, urn, args, bound, include_restricted) if args["parallel"] == true

        query = Query::Show.new(catalog: catalog, pleiades: @pleiades, tibetan_words: @tibetan_words,
                                scan_anchors: @scan_anchors)
        result = query.run(urn)
        return urn_not_found(urn) if result.nil?
        return withheld(urn, result.license_class) if withhold?(result.license_class, include_restricted)

        payload = case result
                  when Query::Show::PassageResult then passage_payload(result)
                  when Query::Show::DocumentResult then document_payload(result, bound)
                  when Query::Show::RangeResult then range_payload(result, bound)
                  # A dictionary-entry urn (the ones nabu_define prints) resolves to the
                  # define payload shape (P22-2), license-withheld by the same rule.
                  when Query::Define::Result then define_payload(result)
                  end
        payload = segmented_payload(query, result, payload) if args["segmented"] == true
        payload = senses_payload(catalog, result, payload) if args["senses"] == true
        # Owner notes ride BY DEFAULT (P24-1: "your own library metadata is
        # useful context") — and only here, after the withhold gate, so a
        # note can never leak a withheld text's content frame.
        json(attach_notes(catalog, result, payload))
      rescue Query::Range::Error => e
        tool_error(e.message)
      end

      # -- show internals ------------------------------------------------------------

      def passage_payload(result)
        {
          type: "passage", urn: result.urn, language: result.language,
          license_class: result.license_class, source: result.source_slug,
          document_urn: result.document_urn, document_title: result.document_title,
          text: result.text, sequence: result.sequence, revision: result.revision,
          withdrawn: result.withdrawn,
          provenance: result.provenance.map { |e| { event: e.event, tool: e.tool, at: e.at.to_s } }
        }.merge(credit_field(result)).merge(meter_field(result)).merge(findspot_field(result))
          .merge(lect_field(result)).merge(timeline_field(result))
      end

      # The resolved lect (P59-3): merged only when the document carries a
      # materialized lect facet row — the one surface that sees per-document
      # journal rulings. "No row means identity" (P58-4), so a bare-code
      # document's payload stays byte-identical and the key never appears
      # carrying a mere echo of `language`. P81 U-5: the facet row's
      # provenance basis rides as lect_basis, and where the ruling behind it
      # states a tier the :lect_tier certainty object merges below certain
      # (the empty-hash idiom — certain and untiered bases add no key).
      def lect_field(result)
        return {} unless result.respond_to?(:lect) && result.lect

        field = { lect: result.lect }
        basis = result.respond_to?(:lect_basis) ? result.lect_basis : nil
        return field unless basis

        field[:lect_basis] = basis
        gloss = Nabu::LectGloss.payload(basis, code: result.language, rules: @lect_rules,
                                               override_tiers: @lect_override_tiers)
        field.merge(gloss)
      end

      # The meter enrichment (P44-3, mirroring the CLI's P44-7 meter line):
      # merged only when the passage carries a scansion — every unscanned
      # passage's payload stays byte-identical, and the key never appears
      # empty. producer is the enrichments row's model ("pedecerto",
      # "hypotactic") — provenance on the claim, per the enrichment doctrine.
      def meter_field(result)
        return {} unless result.respond_to?(:meter) && result.meter

        field = { meter: result.meter.meter, pattern: result.meter.pattern, producer: result.meter.producer }
        # P152: the scansion lane's machine rows carry their grade; gold
        # rows keep the frozen three-key shape byte-identical.
        field[:grade] = result.meter.grade if result.meter.grade
        { meter: field }
      end

      # The findspot facts (P44-3, mirroring the CLI's P44-2 findspot line):
      # merged only when the document's parse-captured Pleiades id resolved
      # through the local gazetteer dump — an absent dump, absent id, or
      # unknown id all leave the payload byte-identical (the CLI's exact
      # degradation; the LiLa precedent).
      def findspot_field(result)
        return {} unless result.respond_to?(:findspot) && result.findspot

        spot = result.findspot
        block = { pleiades_id: spot.id, title: spot.title, place_types: spot.place_types }
        # The reference envelope (contract bump 2026-10-22): the served
        # gazetteer facts carry the gazetteer's attribution — source,
        # license verbatim from its manifest, the place's upstream URI —
        # exactly as the nabu_place card does.
        attribution = Envelope.place_attribution("pleiades", spot.id)
        block[:attribution] = attribution if attribution
        { findspot: block }
      end

      # The timeline block (P76 U-2 — the uncertainty survey's biggest
      # measured gap): merged only when the document carries an axis row —
      # undated documents' payloads stay byte-identical (the empty-hash
      # idiom). Structured, never prose: signed years, the precision word
      # verbatim, place fields as stored. `certainty` (the precision
      # carrier) and `place_certainty` (the cataloguer's trailing "?")
      # merge only below certain (conventions §12).
      def timeline_field(result)
        return {} unless result.respond_to?(:timeline) && result.timeline

        line = result.timeline
        block = { not_before: line.not_before, not_after: line.not_after,
                  precision: line.precision, place: line.place_name,
                  place_ref: line.place_ref, date_raw: line.date_raw,
                  axis_source: line.axis_source, date_class: line.date_class }.compact
        block.merge!(Nabu::Certainty.payload(:hgv_precision, line.precision)) if line.precision
        if line.place_name.to_s.strip.end_with?("?")
          block[:place_certainty] = Nabu::Certainty.payload(:cataloguer_query, "?").fetch(:certainty)
        end
        { timeline: block }
      end

      # The source-level credit (P43-2): merged into a text-serving payload only
      # when the source carries one (the grant's "clearly indicated wherever
      # displayed" duty) — an empty hash for every ordinary source, so existing
      # payloads are byte-identical and the key never appears uncredited.
      # Split note: also read by nabu_search's lanes (tools/search.rb); kept with its primary user.
      def credit_field(result)
        return {} unless result.respond_to?(:credit)

        result.credit.to_s.strip.empty? ? {} : { credit: result.credit }
      end

      def document_payload(result, bound)
        total = result.passages.size
        header(result).merge(
          type: "document",
          passages: passage_lines(result, result.passages.first(bound)),
          note: if total > bound
                  "showing #{bound} of #{total} passages — use a range urn " \
                    "#{result.urn}:<start>-<end> to slice the rest"
                else
                  "#{total} passages"
                end
        )
      end

      def range_payload(result, bound)
        shown = result.passages.first(bound)
        header(result).merge(
          type: "range", start_urn: result.start_urn, end_urn: result.end_urn,
          total: result.total, passages: passage_lines(result, shown),
          note: "#{shown.size} of #{result.total} document passages" +
                (result.passages.size > bound ? " (range truncated at #{bound} — narrow the range)" : "")
        )
      end

      def header(result)
        {
          urn: result.urn, title: result.title, language: result.language,
          license_class: result.license_class, source: result.source_slug,
          revision: result.revision, withdrawn: result.withdrawn,
          retired_upstream: result.retired_upstream
        }.merge(credit_field(result)).merge(findspot_field(result)).merge(timeline_field(result))
          .merge(kind_field(result))
      end

      # The kind axis (P100-5, mirroring the CLI's P99 kind line): merged only
      # when the document carries facet="kind" rows — an unclassified
      # document's payload stays byte-identical and the key never appears
      # empty (the meter/findspot idiom). Each row is {value, raw}: value the
      # ruled class path (multi-label documents list several), raw the
      # upstream vocabulary verbatim, absent when the mapping had none.
      def kind_field(result)
        return {} unless result.respond_to?(:facets)

        rows = result.facets.select { |facet| facet.facet == "kind" }
        return {} if rows.empty?

        { kind: rows.map { |facet| { value: facet.value, raw: facet.raw }.compact } }
      end

      # Owner notes (P24-1), served BY DEFAULT on show/define payloads:
      # merged AFTER the withhold gate, so a note on a withheld document is
      # withheld with it — a note must never leak a withheld text's content
      # frame. Documents additionally carry their passage-note child count.
      # A catalog predating migration 015 has no lane, silently.
      # Split note: also read by nabu_define (tools/define.rb); kept with its primary user.
      def attach_notes(catalog, result, payload)
        reader = Query::Notes.new(catalog: catalog)
        return payload unless reader.available?

        notes = reader.for_urn(result.urn)
        payload = payload.merge(notes: notes.map { |note| note_payload(note) }) unless notes.empty?
        if result.is_a?(Query::Show::DocumentResult)
          children = reader.child_count(result.urn)
          payload = payload.merge(passage_note_count: children) if children.positive?
        end
        payload
      end

      def note_payload(note)
        base = { topic: note.topic, added: note.added, note: note.note }
        note.tags.empty? ? base : base.merge(tags: note.tags)
      end

      # nabu_show `segmented` (P54-2): the CLI's --segmented under the frozen
      # additive contract. Applicable (a Tibetan row, nabu-data synced): each
      # passage record gains a present-only "segmented" key — the SAME
      # space-joined rendering the CLI prints (Query::Show#segmented_text,
      # the one-serializer rule). Not applicable: a present-only top-level
      # "segmentation_note" mirrors the CLI's one honest note line. Existing
      # keys never change; flag off = byte-identical payloads.
      def segmented_payload(query, result, payload)
        language = result.respond_to?(:language) ? result.language : nil
        note = query.segmentation_note(language)
        return payload.merge(segmentation_note: note) if note

        case result
        when Query::Show::PassageResult
          payload.merge(segmented: query.segmented_text(result.text))
        when Query::Show::DocumentResult, Query::Show::RangeResult
          payload.merge(passages: payload.fetch(:passages).map do |line|
            line.merge(segmented: query.segmented_text(line.fetch(:text)))
          end)
        else
          payload
        end
      end

      # nabu_show `senses` (the CLI's show --senses, Query::Senses): each
      # shown passage's citing tokens, read off the annotations the show
      # already loaded (no index needed), as a present-only `senses` list
      # per passage record; every cited id the shelf holds resolves once in
      # the top-level `sense_entries` map. Not applicable (no facet map, a
      # dictionary entry, a source with no ruled token senses): one
      # top-level `senses_note`. Flag off = byte-identical payloads.
      def senses_payload(catalog, result, payload)
        return payload.merge(senses_note: NO_FACET_MAP_NOTE) unless @facet_map
        return payload.merge(senses_note: "token senses apply to corpus passages only") \
          unless result.respond_to?(:source_slug)

        senses = Query::Senses.new(catalog: catalog, facet_map: @facet_map)
        if senses.misc_keys(result.source_slug).empty?
          return payload.merge(senses_note: "no token senses are ruled for #{result.source_slug} " \
                                            "(config/facet_map.yml token_fields)")
        end

        payload, ids = case result
                       when Query::Show::PassageResult then passage_senses(senses, result, payload)
                       else listed_senses(senses, result, payload)
                       end
        return payload.merge(senses_note: "no token senses stored for the shown passage(s)") if ids.empty?

        entries = senses.entries_for(ids)
        payload.merge(sense_entries: entries.sort_by { |id, _| [id.to_i, id] }.to_h do |id, entry|
          [id, { headword: entry.headword, gloss: entry.gloss }]
        end)
      end

      def passage_senses(senses, result, payload)
        cited = senses.token_senses(result.annotations, source: result.source_slug)
        return [payload, []] if cited.empty?

        [payload.merge(senses: cited.map { |token, ids| sense_token_row(token, ids) }), cited.flat_map(&:last)]
      end

      # The listed passages (document/range payloads) zip the result's
      # passage lines in order — passage_lines kept them aligned.
      def listed_senses(senses, result, payload)
        ids = []
        lines = payload.fetch(:passages).each_with_index.map do |line, index|
          cited = senses.token_senses(result.passages.fetch(index).annotations, source: result.source_slug)
          next line if cited.empty?

          ids.concat(cited.flat_map(&:last))
          line.merge(senses: cited.map { |token, ids_of| sense_token_row(token, ids_of) })
        end
        [payload.merge(passages: lines), ids.uniq]
      end

      # One citing token: {form, lemma, ids} — lemma dropped when it is the
      # form itself (the CLI's "form (lemma)" rule).
      # +token+ is a stored token hash (with its +ids+) or a Senses::Token.
      # Split note: also read by nabu_search's sense lane; kept with its primary user.
      def sense_token_row(token, ids = nil)
        form, lemma = token.is_a?(Hash) ? token.values_at("form", "lemma") : [token.form, token.lemma]
        ids ||= token.ids
        row = { form: form }
        row[:lemma] = lemma unless lemma.nil? || lemma == form
        row.merge(ids: ids)
      end

      # Every listed passage carries language + license_class: both are
      # document-effective values (a passage's effective license IS its
      # document's), so the contract holds mechanically.
      def passage_lines(document, lines)
        lines.map do |line|
          { urn: line.urn, language: document.language, license_class: document.license_class,
            text: line.text, withdrawn: line.withdrawn }
        end
      end

      def show_parallel(catalog, urn, args, bound, include_restricted)
        lang = string_arg(args, "parallel_lang") || "eng"
        # The links journal rides along (P48-r2) so kind=translation edges
        # pair cross-source at folio grain — the CLI's show --parallel parity.
        result = Query::Parallel.new(catalog: catalog, journal: resolve(@links)).run(urn, lang: lang)
        return urn_not_found(urn) if result.nil?

        left_license = document_license(catalog, result.left.urn)
        return withheld(result.left.urn, left_license) if withhold?(left_license, include_restricted)
        return note("no #{lang} parallel edition of this work in the catalog for #{urn}") if result.right.nil?

        right_license = document_license(catalog, result.right.urn)
        return withheld(result.right.urn, right_license) if withhold?(right_license, include_restricted)

        json(parallel_payload(result, bound, left_license, right_license))
      rescue Query::Range::Error, Query::Parallel::TranslationMismatch => e
        tool_error(e.message)
      end

      def parallel_payload(result, bound, left_license, right_license)
        shown = result.groups.first(bound)
        {
          type: "parallel",
          left: side_payload(result.left, left_license),
          right: side_payload(result.right, right_license),
          rows: shown.map { |group| parallel_row(group, result, left_license, right_license) },
          note: "#{shown.size} of #{result.groups.size} aligned rows" +
            (result.groups.size > bound ? " (truncated at #{bound} — use a range urn to slice)" : "")
        }
      end

      def side_payload(side, license)
        { urn: side.urn, title: side.title, language: side.language, license_class: license }
      end

      # One aligned row per span-group (P8-1b). left is the anchor/original
      # line, right the translation; a coarse block also carries the coverage
      # fields (anchor + the covered original suffix span, and the clip note
      # when a slice shows only part of it) so a model knows one translation
      # block owns the whole Greek span, not just the one line quoted as left.
      def parallel_row(group, result, left_license, right_license)
        original = group.originals.first
        row = {
          suffix: original&.suffix || group.anchor,
          left: parallel_line(original, result.left.language, left_license),
          right: parallel_line(group.translation, result.right.language, right_license)
        }
        return row unless group.kind == :block

        row.merge!(anchor: group.anchor, covers_first: group.covers_first,
                   covers_last: group.covers_last, clipped: group.clipped)
        row.merge!(shown_first: group.shown_first, shown_last: group.shown_last) if group.clipped
        row
      end

      def parallel_line(line, language, license)
        return nil if line.nil?

        { urn: line.urn, language: language, license_class: license,
          text: line.text, withdrawn: line.withdrawn }
      end
    end
  end
end
