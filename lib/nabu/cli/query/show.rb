# frozen_string_literal: true

# Nabu::CLI — `nabu show` (passage/document/range, --random, --parallel).
# A partial of lib/nabu/cli/query.rb, which loads it.
module Nabu
  class CLI < Thor
    desc "show URN", "Show a passage or document by urn (withdrawn items shown, flagged)"
    long_desc <<~HELP, wrap: false
      Inspect one passage or one whole document by urn. Unlike search and
      export, show hides nothing: withdrawn and retired-upstream items
      appear too, honestly labeled — this is the "what does my collection
      actually hold" lens.

      A PASSAGE urn prints the pristine text, its document, effective
      license, revision, and the full provenance trail (loaded / revised /
      withdrawn / restored / retired events with timestamps) — the
      passage's complete life story.

      A DOCUMENT urn prints the header (title, language, source, license,
      revision, any withdrawn/retired flag) and every passage in citation
      order, listed as :suffixes relative to the document urn printed once
      above; --full-urn restores absolute urns for copy-paste. Long
      documents: pipe to less.

      urn shapes across the corpus:
        CTS editions   urn:cts:greekLit:tlg0012.tlg002.perseus-grc2       (document)
                       urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1   (book 1, line 1)
        papyri (DDbDP) urn:nabu:ddbdp:aegyptus:89:240:b2:5
                       (:b2 = implicit restart block — an unlabeled column/
                        fragment where the edition's line numbers restart)
        treebanks      urn:nabu:proiel:afnik:194690                     (sentence)
                       urn:nabu:ud:gothic-proiel:got_proiel-ud-dev:37589

      RANGES (URN:<start>-<end>): a document urn plus two citation suffixes
      joined by a hyphen prints an INCLUSIVE, sequence-ordered slice of that
      one document between the endpoints — both endpoints must resolve to
      existing passages of the same document (a clear error names whichever
      fails; a start after its end is refused, suggesting a swap). The slice
      is by STORED sequence, whatever citation shapes lie between: a papyri
      restart block (:b2, an implicit column/fragment) is sliced straight
      through. Precedence: a literal passage urn is resolved FIRST, so a urn
      that itself contains a hyphen is never misparsed as a range; the range
      split is on the LAST hyphen (citation suffixes never contain one, the
      version segment perseus-grc2 does). Ranges compose with --full-urn and
      with --parallel (the range slices the queried edition; pairing then
      applies to the sliced rows only).

      PARALLEL TRANSLATIONS (--parallel [LANG], default eng): for a CTS
      document or passage urn — or an ORACC tablet, whose translation is the
      -en sibling document (P13-4) — find the sibling edition of the SAME
      work in LANG (sources ingest translations only when their registry
      entry sets `translations: true`) and render the two SPAN-GROUPED by
      citation suffix. A verse-for-verse translation pairs line by line —
      :1.1 Greek next to :1.1 English. A card-cited prose translation (both
      English Homers) anchors one block of text at a card's first line: the
      original lines are listed, then the translation ONCE, labeled with its
      coverage in the original's numbering (`eng [:1.1 — covers :1.1–:1.43]`)
      plus a clip note when a range shows only part of a card. ORACC's
      paragraph-grained SAA units render as exactly such blocks over the
      tablet's o.1/r.5 lines. A suffix present in only one edition renders
      honestly one-sided, never fuzzed. Works with --full-urn. Where a
      kind=translation link edge joins documents across sources (the
      Kangyur↔84000 crosswalk), --parallel pairs them at Degé folio/page
      grain — no extra flag.

      Examples:
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
        nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.10
                                                  # Iliad 1.1–1.10, one slice
        nabu show urn:nabu:ddbdp:aegyptus:89:240:1-b2:2
                                                  # a papyrus slice across a restart block
        nabu show urn:nabu:ddbdp:aegyptus:89:240            # whole papyrus
        nabu show urn:nabu:ddbdp:aegyptus:89:240 --full-urn # absolute urns
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-grc2 --parallel
                                                  # Greek + eng, line by line
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.5-1.10 --parallel
                                                  # a mid-card slice: the eng block labeled
                                                  #   "covers :1.1–:1.43; range shows :1.5–:1.10"
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-eng2:1 --parallel grc
                                                  # one translated line + its original
        nabu show urn:nabu:oshb:gen:1:1 --tokens  # + the stored token annotations,
                                                  #   verbatim (form, lemma, osm, …)
        nabu show urn:cts:greekLit:tlg0016.tlg001.perseus-grc2:1.6 --entities
                                                  # + the persons/places marked in it
        nabu show urn:nabu:dcs:5:3363:2612 --senses  # + each token's word senses
        nabu show urn:nabu:quranic-corpus:1:1 --roots  # + each token's root → Lane

      TOKENS (--tokens): appends the passage's stored token annotations as
      one line per token — `form` first, then every key the store holds for
      that token, exactly as stored (the honest raw view; nothing decoded,
      nothing invented). A passage without token annotations, and a
      document/range urn, say so.

      ENTITIES (--entities): appends the names the edition marks INSIDE
      the text — Perseus persName/placeName/name spans, Coptic Scriptorium
      entity spans, DHARMA Deccan person/place tags — one line per record:
      upstream's type, the surface, then any key/identity/ref/subtype,
      verbatim. A document or range urn groups them under each passage's
      :suffix. Search by name across the corpus with `nabu entity NAME`.

      SENSES (--senses): appends the word senses the passage's gold tokens
      cite (DCS WordSem ids, the source's token_fields rule in
      config/facet_map.yml) — one line per citing token, form (lemma) then
      each sense id with its dcs-senses name and gloss; an id the shelf
      does not hold says so. A document or range urn groups them under each
      passage's :suffix. Search by sense with `nabu sense TERM`.

      ROOTS (--roots): appends the consonantal root each stored token of a
      Quranic passage carries (the Quranic Arabic Corpus's Buckwalter ROOT,
      Corpus Coranicum's DMG root) stepped to the dictionary headings that
      file it — Lane's article, its entry count and first entry urn, and
      whether the strict or the looser (weak-radical/reduplication) key
      answered; a root no heading carries says so. `nabu define --root
      ROOT` prints the entries. A document or range urn groups by passage.

      SEGMENTED (--segmented): renders Tibetan-language rows (xct/bod/otb)
      with word boundaries — the stored text with a space inserted at each
      boundary (tokens verbatim, trailing tsheg kept), segmented through
      the published nabu-data xct/segmentation dataset. An off-language
      row, or a box that has not run `nabu sync nabu-data`, prints the
      plain text plus one honest note.

      Use cases: read the real edition text behind a search snippet; audit
      a document's revision/provenance history after a sync; eyeball what
      "withdrawn" or "retired upstream" actually holds; read a Greek work
      you can't sight-read next to its English translation; inspect the
      exact lemma/morphology evidence a treebank stored for one passage.
    HELP
    option :full_urn, type: :boolean, default: false,
                      desc: "List document passages with absolute urns instead of :suffixes"
    option :parallel, type: :string, lazy_default: "eng", banner: "[LANG]",
                      desc: "Align with the same work's LANG edition by citation suffix (default eng)"
    option :random, type: :boolean, default: false,
                    desc: "Show random passages instead of a urn (the eyeball ritual at a source flip)"
    option :source, type: :string, banner: "SLUG",
                    desc: "With --random: draw only from this source (default: the whole corpus)"
    option :lang, type: :string, banner: "CODE",
                  desc: "With --random: draw only passages in this language (grc, lat, … — the multi-lang eyeball)"
    option :count, type: :numeric, default: 1,
                   desc: "With --random: how many passages (default 1, cap #{Nabu::Query::Random::MAX_COUNT})"
    option :tokens, type: :boolean, default: false,
                    desc: "Append the passage's stored token annotations verbatim (form + every key present)"
    option :entities, type: :boolean, default: false,
                      desc: "Append the names the edition marks inside the text (persons, places …), verbatim"
    option :senses, type: :boolean, default: false,
                    desc: "Append the word senses the gold tokens cite (DCS WordSem), resolved against dcs-senses"
    option :roots, type: :boolean, default: false,
                   desc: "Append each Quranic token's root stepped to Lane's Lexicon (QAC Buckwalter, " \
                         "Corpus Coranicum DMG)"
    option :segmented, type: :boolean, default: false,
                       desc: "Render Tibetan (xct/bod/otb) passages with word boundaries " \
                             "(needs the synced nabu-data module)"
    display_option
    def show(urn = nil)
      urn = urn.to_s.strip
      display_mode
      if options[:tokens] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --tokens does not compose with --random/--parallel"
      end
      if options[:segmented] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --segmented does not compose with --random/--parallel"
      end
      if options[:entities] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --entities does not compose with --random/--parallel"
      end
      if options[:senses] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --senses does not compose with --random/--parallel"
      end
      if options[:roots] && (options[:random] || options[:parallel])
        raise Thor::Error, "show: --roots does not compose with --random/--parallel"
      end

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      if options[:random]
        show_random(catalog, urn, config)
        return print_display_footer
      end
      raise Thor::Error, "show: --source requires --random" if options[:source]
      raise Thor::Error, "show: --lang restricts --random draws — give a urn, or add --random" if options[:lang]
      raise Thor::Error, "show: give a urn" if urn.empty?

      if options[:parallel]
        show_parallel(catalog, urn, options[:parallel], config)
        return print_display_footer
      end

      # pleiades: :auto — the findspot line (P44-2) feature-detects the
      # gazetteer dump lazily; nothing loads unless the shown document
      # carries a captured Pleiades id.
      show_query = Nabu::Query::Show.new(catalog: catalog, pleiades: :auto,
                                         scan_anchors: Nabu::Query::ScanAnchors.load_default(config: config))
      result = show_query.run(urn)
      raise Thor::Error, "urn not found: #{urn}" if result.nil?

      # --segmented (P54-2): the word-broken Tibetan rendering. The
      # segmentation is Query::Show's (the one serializer MCP shares); here
      # we only swap texts on a copy of the result — or keep the plain
      # output plus the query layer's one honest note line.
      seg_note = nil
      if options[:segmented]
        seg_note = show_query.segmentation_note(result.respond_to?(:language) ? result.language : nil)
        result = segmented_show_result(show_query, result) if seg_note.nil?
      end

      print_show(result)
      say seg_note if seg_note
      print_show_tokens(result) if options[:tokens]
      print_show_entities(result) if options[:entities]
      print_show_senses(result, catalog: catalog, config: config) if options[:senses]
      print_show_roots(result, catalog: catalog) if options[:roots]
      print_linked_footer(config, result.urn)
      print_notes_footer(catalog, result)
      print_display_footer
    rescue Nabu::Query::Range::Error, Nabu::Query::Random::Error,
           Nabu::Query::Parallel::TranslationMismatch => e
      # A range urn that names two endpoints but can't be honoured (endpoint
      # missing, or reversed), an unknown --random --source, or a --parallel
      # LANG the translation link cannot serve: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    # H9 (P35-6): the skip-with-note rule for a corrupt annotations_json —
    # Show marks the parse failure (ANNOTATIONS_UNREADABLE) and every
    # render that would have used the lane says so.
    ANNOTATIONS_UNREADABLE_NOTE = "stored annotations are unreadable (invalid JSON) — skipped"

    no_commands do
      # `show --random` (P11-9): N random visible passages, each in the standard
      # passage layout — the eyeball ritual at a source flip. A urn alongside
      # --random is contradictory (it picks passages for you); an empty result
      # is an honest note, not an error.
      def show_random(catalog, urn, config)
        raise Thor::Error, "show: --random takes no urn (it picks passages for you)" unless urn.empty?
        return show_random_parallel(catalog, config) if options[:parallel]

        results = Nabu::Query::Random.new(catalog: catalog)
                                     .run(source: options[:source], lang: options[:lang], count: options[:count].to_i)
        if results.empty?
          scope = +""
          scope << " in source #{options[:source]}" if options[:source]
          scope << " in #{options[:lang]}" if options[:lang]
          return say("no passages to show#{scope} (nothing visible — the corpus may be empty or all withdrawn)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          print_show_passage(result)
        end
      end

      # P47-r1 (owner: "elephantine is perfect for --parallel showcase!"):
      # --random composes with --parallel — draw ORIGINALS (the sampler
      # already excludes translation siblings) until one carries a parallel
      # in the requested language, render the paired view; a scope that
      # yields none in the attempt budget (12 draws per requested passage —
      # a retry bound, not a corpus claim) says so honestly.
      def show_random_parallel(catalog, config)
        random = Nabu::Query::Random.new(catalog: catalog)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        parallel = Nabu::Query::Parallel.new(catalog: catalog, journal: journal)
        wanted = options[:count].to_i.clamp(1, Nabu::Query::Random::MAX_COUNT)
        shown = []
        attempts = 0
        while shown.size < wanted && attempts < wanted * 12
          attempts += 1
          draw = random.run(source: options[:source], lang: options[:lang], count: 1).first
          break if draw.nil?
          next if shown.include?(draw.urn)

          # A draw whose translation edge cannot serve the requested lang is
          # simply not a parallel-bearing draw (P48-r2) — keep drawing.
          pair = begin
            parallel.run(draw.urn, lang: options[:parallel])
          rescue Nabu::Query::Parallel::TranslationMismatch
            nil
          end
          next if pair.nil? || pair.right.nil?

          say "" unless shown.empty?
          print_parallel(pair)
          shown << draw.urn
        end
        return unless shown.empty?

        scope = options[:source] ? " in source #{options[:source]}" : ""
        say "no parallel-bearing draw#{scope} after #{attempts} attempts — the scope may hold no " \
            "#{options[:parallel]} siblings (`show <urn> --parallel` pairs a known document; " \
            "`show --random` alone draws unpaired)"
      ensure
        journal&.disconnect
      end

      # Render `show`: a passage in the context of its document, or a document
      # header plus its passages in sequence. Withdrawn items ARE shown, tagged.
      def print_show(result)
        case result
        when Nabu::Query::Show::PassageResult then print_show_passage(result)
        when Nabu::Query::Show::DocumentResult then print_show_document(result)
        when Nabu::Query::Show::RangeResult then print_show_range(result)
        when Nabu::Query::Define::Result then print_define_entry(result)
        end
      end

      # `show --segmented` (P54-2): the result with every passage text
      # word-broken through Query::Show#segmented_text — a copy, so every
      # existing print path renders unchanged (tokens verbatim, spaces at
      # word boundaries). Only reached when the segmentation note is nil
      # (a Tibetan row with the nabu-data dataset synced).
      def segmented_show_result(query, result)
        case result
        when Nabu::Query::Show::PassageResult
          result.with(text: query.segmented_text(result.text))
        when Nabu::Query::Show::DocumentResult, Nabu::Query::Show::RangeResult
          result.with(passages: result.passages.map { |line| line.with(text: query.segmented_text(line.text)) })
        else
          result
        end
      end

      # The source-level credit line (P43-2, the grant's "clearly indicated
      # wherever displayed" duty), shown only when the source carries one — a
      # nil/blank credit (every ordinary source) prints nothing.
      def print_credit(result)
        credit = result.credit.to_s.strip
        say "  credit: #{credit}" unless credit.empty?
      end

      # P44-7: the meter line — shown only when the passage carries a scansion
      # enrichment (pedecerto over held Perseus-Latin verse), byte-identical
      # absence otherwise. "meter: H DSDS (pedecerto)": metrical code, foot
      # pattern (omitted when empty), producer.
      def print_meter(passage)
        meter = passage.meter
        return if meter.nil?

        pattern = meter.pattern.to_s.strip
        code = [meter.meter.to_s.strip, pattern].reject(&:empty?).join(" ")
        # P152: a silver row says so — machine scansion, never gold
        say "  meter: #{code} (#{meter.producer}#{', silver — machine scansion' if meter.silver?})"
      end

      # P44-2: the findspot line — shown only when the document's parse-
      # captured Pleiades id resolves through the local gazetteer dump
      # (title + place types; maps and coordinate math are out by design).
      # Absent dump, absent id, unknown id: no line, byte-identical output.
      def print_findspot(result)
        spot = result.findspot
        return if spot.nil?

        if spot.id.nil?
          # P69-1: the coordinates findspot — the source's own WGS84 pair,
          # no gazetteer (rundata's SRDB columns).
          pair = format("%<lat>.5f, %<lon>.5f", lat: spot.lat, lon: spot.lon)
          say "  findspot: #{[spot.title, pair].compact.join(' — ')}"
          return
        end
        types = spot.place_types.empty? ? "" : " (#{spot.place_types.join(' · ')})"
        say "  findspot: #{spot.title} — Pleiades #{spot.id}#{types}"
      end

      # P61-3 (D60-b): the artifact-script line — only where the original
      # artifact's script DIFFERS from the held surface (the lane is minted
      # on difference by construction). Tag + config note, honest and short.
      # P76 U-7: the upstream script_uncertain flag glosses "(script
      # uncertain)" — on the artifact line when one exists, else on its own
      # honest line (the flag can ride documents outside the differs-only
      # lane).
      def print_artifact(result)
        artifact = result.artifact
        return if artifact.nil?

        if artifact.script
          note = artifact.note ? " — #{artifact.note}" : ""
          flag = artifact.uncertain ? " (script uncertain)" : ""
          say "  artifact script: #{artifact.script}#{note}#{flag} (held surface differs; see the lect ~axis)"
        elsif artifact.uncertain
          say "  script: (script uncertain — upstream flag)"
        end
      end

      def print_show_passage(passage)
        say "#{passage.urn}#{" [#{passage.language}]" if passage.language}#{withdrawn_tag(passage.withdrawn)}"
        say "  #{display_text(painted_passage_text(passage), passage.language,
                              source: passage.source_slug, annotations: passage.annotations)}"
        say "  document: #{passage.document_urn}#{" — #{passage.document_title}" if passage.document_title}"
        say "  source: #{passage.source_slug}   license: #{passage.license_class}   " \
            "sequence: #{passage.sequence}   revision: #{passage.revision}"
        print_credit(passage)
        print_lect(passage)
        print_timeline(passage.timeline)
        print_findspot(passage)
        print_meter(passage)
        # H9 (P35-6): a corrupt annotation lane announces itself instead of
        # posing as an unannotated passage.
        say "  note: #{ANNOTATIONS_UNREADABLE_NOTE}" if annotations_unreadable?(passage)
        return if passage.provenance.empty?

        say "  provenance:"
        passage.provenance.each do |event|
          # P112-2: an implicit "loaded" (no per-passage breadcrumb) may
          # carry no timestamp at all — render the event without one.
          stamp = event.at ? "#{event.at}  " : ""
          say "    #{stamp}#{event.event}#{"  #{event.tool}" if event.tool}"
        end
      end

      # `show URN --tokens` (P35-6, the journaled gate find): the honest RAW
      # view of the stored token annotations — one line per token, `form`
      # first, then EVERY other key exactly as stored (lemma/gloss/osm/lang/
      # …, nested values as compact JSON). No display transforms, no
      # invention; a passage without tokens, and a non-passage grain, both
      # say so instead of rendering nothing.
      def print_show_tokens(result)
        unless result.is_a?(Nabu::Query::Show::PassageResult)
          return say "--tokens renders at passage grain — give a passage urn"
        end
        return say ANNOTATIONS_UNREADABLE_NOTE if annotations_unreadable?(result)

        tokens = result.annotations["tokens"]
        tokens = tokens.is_a?(Array) ? tokens.grep(Hash) : []
        return say "no token annotations stored for this passage" if tokens.empty?

        say "tokens (#{tokens.size}):"
        tokens.each { |token| say "  #{token_line(token)}" }
      end

      # One token as `form=… key=…` pairs, form first, stored key order after,
      # non-scalar values as compact JSON — verbatim, never interpreted.
      def token_line(token)
        keys = (["form"] + token.keys).uniq.select { |key| token.key?(key) }
        keys.map do |key|
          value = token[key]
          "#{key}=#{value.is_a?(String) ? value : JSON.generate(value)}"
        end.join("  ")
      end

      # Split note: also used by the entities and senses commands; kept with its primary user.
      def annotations_unreadable?(result)
        result.annotations[Nabu::Query::Show::ANNOTATIONS_UNREADABLE] == true
      end

      def print_unreadable_annotations_count(lines)
        count = lines.count { |line| annotations_unreadable?(line) }
        return unless count.positive?

        say "  note: #{count} #{count == 1 ? 'passage carries' : 'passages carry'} " \
            "unreadable stored annotations (invalid JSON) — skipped"
      end

      def print_show_document(document)
        title = document.title ? " — #{document.title}" : ""
        lang = document.language ? " [#{document.language}]" : ""
        say "#{document.urn}#{title}#{lang}" \
            "#{withdrawn_tag(document.withdrawn, reason: document.withdrawn_reason,
                                                 at: document.withdrawn_at)}#{retired_tag(document)}"
        say "  source: #{document.source_slug}   license: #{document.license_class}   revision: #{document.revision}"
        print_credit(document)
        print_timeline(document.timeline)
        print_findspot(document)
        print_artifact(document)
        print_facets(document.facets, language: document.language)
        say "  passages (#{document.passages.size}):"
        document.passages.each do |line|
          say "    #{passage_label(document, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, document.language,
                              source: document.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(document.passages)
      end

      # Render a range (P7-6): the document header like a document listing, an
      # honest "[N of M passages]" note plus the two endpoint urns, then the
      # inclusive slice as :suffixes (--full-urn restores absolute urns).
      def print_show_range(range)
        title = range.title ? " — #{range.title}" : ""
        lang = range.language ? " [#{range.language}]" : ""
        say "#{range.urn}#{title}#{lang}#{withdrawn_tag(range.withdrawn)}#{retired_tag(range)}"
        say "  source: #{range.source_slug}   license: #{range.license_class}   revision: #{range.revision}"
        print_credit(range)
        print_timeline(range.timeline)
        say "  range: #{range.start_urn} … #{range.end_urn}  " \
            "[#{range.passages.size} of #{range.total} passages]"
        range.passages.each do |line|
          say "    #{passage_label(range, line)}#{withdrawn_tag(line.withdrawn)}  " \
              "#{display_text(line.text, range.language,
                              source: range.source_slug, annotations: line.annotations)}"
        end
        print_unreadable_annotations_count(range.passages)
      end

      # P81 U-5: the lect line — only when the document carries a
      # materialized lect facet row ("no row means identity", P58-4; a
      # bare-code passage prints nothing). The resolution's provenance
      # basis rides in parentheses; where the ruling behind the basis
      # STATES a tier (the rule's tier:, the override row's tier:) the
      # parenthetical glosses through Certainty's :lect_tier carrier
      # instead — certain stays provenance-only ink, deviation is labeled:
      # "lect: arc:mid (probable — rule sefaria-arc-subshelf, approximation)".
      def print_lect(passage)
        return unless passage.lect

        say "  lect: #{passage.lect}#{lect_facet_note(passage.lect_basis, code: passage.language)}"
      end

      # " (<gloss>)" when the basis's ruling states a tier, " (<basis>)"
      # as bare provenance otherwise, "" for a basis-less row (materialized
      # before the P81 basis lane) — shared by the passage lect line and
      # the document facets line.
      def lect_facet_note(basis, code:)
        return "" unless basis

        gloss = Nabu::LectGloss.gloss(basis, code: code, rules: cli_lect_rules,
                                             override_tiers: cli_lect_override_tiers)
        " (#{gloss || basis})"
      end

      # The config-stated tier carriers, memoized per command run (both are
      # small YAML reads; nil rules = no rules file, an honest untiered
      # render).
      def cli_lect_rules
        return @cli_lect_rules if defined?(@cli_lect_rules)

        @cli_lect_rules = Nabu::LectRules.load(Nabu::Config.load.lect_facet_rules_paths)
      end

      def cli_lect_override_tiers
        return @cli_lect_override_tiers if defined?(@cli_lect_override_tiers)

        @cli_lect_override_tiers = Nabu::Lects.override_tiers(Nabu::Config.load.lect_overrides_paths)
      end

      # The timeline line (P15-2), when the document has one. A date span
      # ("113 BCE", "501–700 CE", "≤ 257 BCE") with the informative precision
      # ("low"/"high", not the derived exact/range/year) and the provenance
      # place; place-only rows print as "place:". Undated documents print
      # nothing (an absence, never an error).
      def print_timeline(timeline)
        return if timeline.nil?

        span = Nabu::Timeline.format_span(timeline.not_before, timeline.not_after)
        place = timeline.place_name ? " · #{timeline.place_name}#{place_query_gloss(timeline.place_name)}" : ""
        if span && timeline.date_class == Nabu::Store::SilverDates::DATE_CLASS
          # P122-1: an estimate is never dressed as an upstream date.
          say "  date: #{span} [silver — #{timeline.date_raw}]#{place}"
        elsif span
          say "  date: #{span}#{precision_note(timeline.precision)}#{place}"
        elsif timeline.place_name
          say "  place: #{timeline.place_name}#{place_query_gloss(timeline.place_name)}"
        end
      end

      # P76 U-2 (conventions §12): a genuinely graded precision word routes
      # through Certainty — house tier plus the upstream word verbatim
      # ('(uncertain — hgv "low")'); "high" is certain and SILENT; width
      # words beyond the always-silent exact/range/year keep their plain
      # informative note ("(period)") — width, not doubt.
      def precision_note(precision)
        return "" if %w[exact range year].include?(precision)

        gloss = Nabu::Certainty.gloss(:hgv_precision, precision)
        return " (#{gloss})" if gloss
        return "" if Nabu::Certainty.tier(:hgv_precision, precision) == "certain"

        " (#{precision})"
      end

      # The facets line (P17-2), one compact line and only when faceted:
      # "facets: genre=epitaph (titsep) · province=Latium et Campania …". The
      # raw code rides in parentheses when it differs from the value (the `?`
      # certainty stays visible). P81 U-5: the lect facet's raw is its
      # provenance basis — it renders through the tier gloss (or as the bare
      # basis) exactly like the passage card's lect line.
      def print_facets(facets, language: nil)
        return if facets.nil? || facets.empty?

        kind_rows, rest = facets.partition { |facet| facet.facet == "kind" }
        rendered = rest.map do |facet|
          if facet.facet == "lect"
            "lect=#{facet.value}#{lect_facet_note(facet.raw, code: language)}"
          else
            raw = facet.raw && facet.raw != facet.value ? " (#{facet.raw})" : ""
            "#{facet.facet}=#{facet.value}#{raw}"
          end
        end
        say "  facets: #{rendered.join(' · ')}" unless rest.empty?
        print_kind_line(kind_rows)
      end

      # The kind axis' card line (P99-3, owner-ruled 2026-09-13): every class the
      # document carries on ONE line, multi-label joined with " + ",
      # the upstream claim(s) visible verbatim. A declaration-born row
      # (raw nil — okhc's source_kind) shows no upstream tail.
      def print_kind_line(kind_rows)
        return if kind_rows.empty?

        classes = kind_rows.map(&:value).uniq.join(" + ")
        raws = kind_rows.map(&:raw).compact.uniq
        upstream = raws.empty? ? "" : " — upstream: #{raws.map(&:inspect).join(', ')}"
        say "  kind: #{classes}#{upstream}"
      end

      # Print practice: the document urn appears once in the header, each
      # passage line carries only its changing :suffix (":b2:5"). --full-urn
      # restores absolute urns (copy-paste into `show`/scripts). A passage
      # whose urn doesn't extend the document urn (never minted by our
      # adapters, but data is data) falls back to the full urn.
      # Split note: also used by the entities and senses commands; kept with its primary user.
      def passage_label(document, line)
        return line.urn if options[:full_urn]

        suffix = line.urn.delete_prefix(document.urn)
        suffix == line.urn || suffix.empty? ? line.urn : suffix
      end

      # -- show --parallel (P7-4) ------------------------------------------

      # Resolve + align + render, with the honest failure modes: unknown urn
      # (exit 1, same message as plain show), no LANG sibling or translation
      # edge in the catalog (exit 1, names the language), and a translation
      # edge that cannot serve LANG (exit 1 via TranslationMismatch, naming
      # the language that would work). The links journal rides along
      # read-only so the P48-r2 kind=translation edges (Kangyur↔84000) pair
      # cross-source with no extra flag.
      def show_parallel(catalog, urn, lang, config)
        journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
        result = Nabu::Query::Parallel.new(catalog: catalog, journal: journal).run(urn, lang: lang)
        raise Thor::Error, "urn not found: #{urn}" if result.nil?
        if result.right.nil?
          raise Thor::Error, "no #{lang} parallel edition of this work in the catalog for #{urn} " \
                             "(--parallel pairs sibling CTS editions within one source, or " \
                             "cross-source over a kind=translation link edge; is " \
                             "`translations: true` set and the source resynced?)#{align_hint(urn, config)}"
        end

        print_parallel(result)
      ensure
        journal&.disconnect
      end

      # Cosmetic rider (P11-8): --parallel's "is translations: true set" hint is
      # misleading for a CROSS-source text (Vulgate/LXX/WEB have no sibling CTS
      # edition to pair). When the urn is a registered alignment witness, point
      # at `nabu align` instead — the hub built for exactly this.
      def align_hint(urn, config)
        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        witnessed = registry.works.any? do |work|
          work.witnesses.any? do |witness|
            witness.document_urns.any? { |doc| urn == doc || urn.start_with?("#{doc}:") }
          end
        end
        witnessed ? " — this text is an alignment-hub witness; try `nabu align REF` for cross-source alignment" : ""
      rescue Nabu::ValidationError
        ""
      end

      # Render the alignment (P8-1b span-grouped): both document headers, the
      # paired/blocks/one-sided counts, then one span-group at a time. A verse
      # pair keeps the compact pair form (byte-identical to pre-P8-1b); a coarse
      # block prints the original lines first, then the translation once with
      # its full coverage (and a clip note when a slice shows only part of it);
      # one-sided rows dash the missing side. Withdrawn passages are shown,
      # tagged (show-family).
      def print_parallel(result)
        say format_parallel_side(result.left)
        say "  parallel: #{format_parallel_side(result.right)}"
        say "  #{parallel_counts(result)}"
        width = [result.left.language.to_s.length, result.right.language.to_s.length].max + 2
        result.groups.each { |group| print_parallel_group(group, result, width) }
      end

      def print_parallel_group(group, result, width)
        case group.kind
        when :pair        then print_parallel_pair(group, result, width)
        when :block       then print_parallel_block(group, result, width)
        when :original    then print_parallel_one_sided(group, result, width, side: :left)
        when :translation then print_parallel_one_sided(group, result, width, side: :right)
        end
      end

      # Verse pair / one-sided rows: the pre-P8-1b two-line form, the suffix (or
      # absolute urn under --full-urn) over one line per language, "—" for the
      # absent side. Kept byte-identical so verse-for-verse output never shifts.
      def print_parallel_pair(group, result, width)
        line = group.originals.first
        say "  #{options[:full_urn] ? line.urn : group.anchor}"
        say "    #{parallel_line(result.left.language, line, width)}"
        say "    #{parallel_line(result.right.language, group.translation, width)}"
      end

      def print_parallel_one_sided(group, result, width, side:)
        present = side == :left ? group.originals.first : group.translation
        say "  #{options[:full_urn] ? present.urn : present.suffix}"
        left = side == :left ? present : nil
        right = side == :right ? present : nil
        say "    #{parallel_line(result.left.language, left, width)}"
        say "    #{parallel_line(result.right.language, right, width)}"
      end

      # Coarse block: each owned original as a suffix-labeled left line, then
      # the translation once, labeled with its full coverage in the original's
      # numbering plus a clip note when the shown slice is only part of it.
      def print_parallel_block(group, result, width)
        group.originals.each do |line|
          say "  #{options[:full_urn] ? line.urn : line.suffix}"
          say "    #{parallel_line(result.left.language, line, width)}"
        end
        say "  #{result.right.language} #{block_coverage(group)}"
        say "    #{display_text(group.translation.text, result.right.language)}" \
            "#{withdrawn_tag(group.translation.withdrawn)}"
      end

      # `[:1.1 — covers :1.1–:1.43; range shows :1.5–:1.10]` — the anchor, the
      # full ownership span, and (only when clipped) the shown sub-range.
      def block_coverage(group)
        covers = "covers #{group.covers_first}–#{group.covers_last}"
        clip = group.clipped ? "; range shows #{group.shown_first}–#{group.shown_last}" : ""
        "[#{group.anchor} — #{covers}#{clip}]"
      end

      def format_parallel_side(side)
        "#{side.urn}#{" — #{side.title}" if side.title}#{" [#{side.language}]" if side.language}"
      end

      # Honest grouped arithmetic: paired counts 1:1 verse pairs; the blocks
      # clause (and its owned-line total) appears only when there ARE coarse
      # blocks, so verse-for-verse output stays byte-identical to pre-P8-1b.
      def parallel_counts(result)
        paired = result.groups.count { |group| group.kind == :pair }
        blocks = result.groups.select { |group| group.kind == :block }
        left_only = result.groups.count { |group| group.kind == :original }
        right_only = result.groups.count { |group| group.kind == :translation }
        block_lines = blocks.sum { |group| group.originals.size }
        blocks_clause = blocks_clause(blocks.size, block_lines)
        "aligned by citation: #{paired} paired, #{blocks_clause}" \
          "#{left_only} #{result.left.language} only, #{right_only} #{result.right.language} only"
      end

      # The blocks clause appears only when there ARE coarse blocks, so
      # verse-for-verse output stays byte-identical to the pre-P8-1b header.
      def blocks_clause(blocks, lines)
        return "" if blocks.zero?

        "#{plural(blocks, 'block')} covering #{plural(lines, 'line')}, "
      end

      def parallel_line(language, line, width)
        label = language.to_s.ljust(width)
        return "#{label}—" if line.nil?

        "#{label}#{display_text(line.text, language)}#{withdrawn_tag(line.withdrawn)}"
      end

      # +reason:+/+at:+ (P93-2): the document card names WHY and WHEN it
      # left when the loader recorded it; a bare flag stays the honest
      # render for pre-P93 withdrawals and passage lines.
      def withdrawn_tag(withdrawn, reason: nil, at: nil)
        return "" unless withdrawn

        detail = [reason, at.respond_to?(:strftime) ? at.strftime("%Y-%m-%d") : at].compact.join(", ")
        detail.empty? ? "  (withdrawn)" : "  (withdrawn: #{detail})"
      end

      # P5-2: upstream scrapped the file; the attic kept it. Live, labeled.
      def retired_tag(document)
        document.retired_upstream ? "  (retired upstream)" : ""
      end

      # The `show` footer (P16-1): one "linked:" line, ONLY when the links
      # journal holds edges touching this urn — zero-signal silence otherwise
      # (no journal, no edges, nothing printed). Read-only, absent-file-safe.
      def print_linked_footer(config, urn)
        journal = Nabu::Store::LinkLayers.open_readonly(config)
        return if journal.nil?

        counts = Nabu::Store::LinksJournal.kind_counts(journal, urn)
        return if counts.empty?

        say "  linked: #{counts.sort_by { |kind, _| kind }.map { |kind, count| "#{count} #{kind}" }.join(', ')}"
      ensure
        journal&.disconnect
      end
    end
  end
end
