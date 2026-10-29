# frozen_string_literal: true

# Nabu::CLI — the `nabu export` subcommand family (ExportCLI) and the passage
# stream it drives. Carved out of lib/nabu/cli.rb, the registry that loads it.
module Nabu
  # `nabu export` — the research exporter (P121-1, architecture §18): each
  # table command streams one documented query (Nabu::Export) to CSV or
  # JSONL under exports/ with a license manifest beside it. The passage
  # stream is the family's DEFAULT command, so the long-standing
  # `nabu export --format plain|jsonl ...` spelling routes to `passages`
  # unchanged. Every table is read-only on every database.
  class ExportCLI < Thor
    include DurationFormat

    namespace "export"

    default_command :passages

    def self.exit_on_failure?
      true
    end

    OVERVIEW = <<~HELP
      Get matrices out of the library.

      Tables — each writes <table>.csv (or .jsonl with --format jsonl) into
      exports/ (--out DIR elsewhere) plus <table>.manifest.yml beside it:
      generated_at, the filters applied, the row total, every column
      documented, and every source drawn on with its license class. Default
      exports include everything (local research use); --license-class
      open,attribution keeps only rows whose every source is in the list —
      a redistributable set, and the manifest proves what it drew on.

        documents   one row per live document (--with-axes: lect, script,
                    date envelope, place, genre, kind)
        links       the links journal's edges with run provenance and each
                    endpoint's source + license (--dated: endpoint dates)
        lemmas      the lemma × language × century × grade × source
                    attestation matrix, from the precompiled lemma rollup
        align       verse pairs off the alignment hub — base witness against
                    each other witness per ref (--with-morph: gold tokens
                    with lemma + decoded morphology; jsonl by default)
        collation   the align --collate apparatus as rows — per anchor ref,
                    each witness reading, its role and its variants
        passages --stratum language,century,script
                    a stratified, seeded passage sample (passage_sample.*)

      The passage stream (stdout, no manifest) is the default command:
        passages    --format plain | jsonl — jsonl lines carry the parsed
                    annotations (lemmas/morphology where the source has them)

      Examples:
        nabu export documents --with-axes
        nabu export documents --lang lat --from -200 --to 200 --license-class open,attribution
        nabu export links --kind parallel --dated --format jsonl
        nabu export align MARK 2 --with-morph
        nabu export collation --work nt --base ccmh-marianus
        nabu export passages --stratum language,century --per-cell 50 --exclude-ocr --format jsonl
        nabu export --format jsonl --lang got > gothic.jsonl

    HELP

    # `nabu help export` / `nabu export --help`: the family overview, then
    # Thor's command list.
    def self.help(shell, *)
      shell.say OVERVIEW
      super
    end

    # The options every table command shares.
    def self.table_options
      option :format, type: :string, default: "csv", banner: "csv|jsonl", desc: "Output format"
      option :out, type: :string, banner: "DIR", desc: "Output directory (default: exports/ at the tree root)"
      option :license_class, type: :string, banner: "CLASS[,CLASS...]",
                             desc: "Keep only rows whose every source is in these license classes " \
                                   "(open, attribution, nc, odbl, research_private, restricted)"
    end

    desc "passages", "Stream non-withdrawn passages to stdout as plain text or JSONL (the default command)"
    long_desc <<~HELP, wrap: false
      Stream the live corpus to stdout, one passage per line — the
      longevity-hedge exit formats: the data must survive the code.
      Withdrawn passages are excluded; retired-upstream documents are
      INCLUDED (they are part of your collection — that is the point of
      keeping them). Streaming end to end: constant memory at any corpus
      size, so piping a million passages is fine. The default command of
      `nabu export`: `nabu export --format ...` means exactly this.

      Formats:
        plain   text only, internal newlines collapsed to one space
        jsonl   one JSON object per line: urn, language, text,
                text_normalized, annotations — annotations is a real nested
                object carrying lemmas/morphology where the source provides
                them (the treebanks: UD, PROIEL, TOROT)
        conllu  arrives with the enrichment phase (needs the token model)

      Same --lang / --license / --source filters as search.

      Stratified sample (--stratum): instead of the stream, write
      exports/passage_sample.csv (or .jsonl) + its manifest — a seeded,
      reproducible sample whose cells are the chosen strata:

        language  the passage's language
        century   signed century of the document envelope's midpoint
                  (-1 = 1st c. BCE; undated is its own cell)
        script    the dominant script of the held text (ISO 15924, latn…)
        source    the source slug

      Allocation is EQUAL per cell by default — up to --per-cell N (default
      #{Nabu::Export::PassageSample::DEFAULT_PER_CELL}) passages per cell, smaller cells taken whole — because
      a proportional draw just reproduces the library's skew and starves
      the small cells; --proportional TOTAL splits TOTAL by population
      share instead. Every row carries cell_population, cell_sampled and
      weight (population / sampled) to restore population estimates. The
      draw ranks passages by sha256(seed:urn): the same --seed over the same
      library draws the same urns. --exclude-ocr drops documents flagged as
      OCR text (metadata text_nature machine-ocr / uncorrected-ocr) and KEEPS
      the corrected-ocr / ocr-origin labels (OCR corrected upstream, or of
      unstated correction); --exclude-source drops any further sources you
      know to be OCR-derived. Rows: urn,
      document_urn, source, language, century, script, stratum,
      cell_population, cell_sampled, weight, license_class, text.

      Examples:
        nabu export --format plain --lang got > gothic.txt
        nabu export --format jsonl --source ccmh > ccmh.jsonl
        nabu export --format jsonl --license open | jq -r .urn
        nabu export --format jsonl --lang chu | jq '.annotations' | head
        nabu export passages --stratum language,century,script --format csv
        nabu export passages --stratum language,century --per-cell 50 --exclude-ocr --seed 7 --format jsonl
        nabu export passages --stratum language --proportional 5000 --license-class open,attribution --format csv

      Use cases: feed a corpus slice to external NLP tooling; a license-clean
      subset for anything you plan to publish; plain-text dumps for grep-scale
      workflows or personal backups independent of nabu itself; a balanced,
      citable thesis sample (--stratum).
    HELP
    option :format, type: :string, required: true, desc: "plain | jsonl (with --stratum: csv | jsonl)"
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat; with --stratum a list)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :source, type: :string, banner: "SLUG",
                    desc: "Restrict to one source (`nabu list` names the slugs; with --stratum a list)"
    option :axis, type: :string, banner: "NAME[,NAME...]",
                  desc: "Restrict to the members of one or more research axes (config/axes.yml) — the " \
                        "multi-source generalization of --source"
    option :stratum, type: :string, banner: "NAME[,NAME...]",
                     desc: "Write a stratified sample instead of the stream: cells by language, century, " \
                           "script, source"
    option :per_cell, type: :numeric, banner: "N",
                      desc: "With --stratum: passages per cell (equal allocation, the default: " \
                            "#{Nabu::Export::PassageSample::DEFAULT_PER_CELL})"
    option :proportional, type: :numeric, banner: "TOTAL",
                          desc: "With --stratum: TOTAL passages split across cells by population share"
    option :seed, type: :numeric, banner: "N", desc: "With --stratum: the draw's seed (default 0)"
    option :exclude_ocr, type: :boolean, desc: "With --stratum: drop documents flagged as OCR text"
    option :exclude_source, type: :string, banner: "SLUG[,SLUG...]", desc: "With --stratum: drop these sources"
    option :out, type: :string, banner: "DIR", desc: "With --stratum: output directory (default: exports/)"
    option :license_class, type: :string, banner: "CLASS[,CLASS...]",
                           desc: "With --stratum: keep only rows whose source is in these license classes"
    def passages
      return stratified_passages if options[:stratum]

      stray = STRATUM_ONLY.find { |name| !options[name].nil? }
      raise Thor::Error, "export passages: --#{stray.to_s.tr('_', '-')} needs --stratum" if stray

      Nabu::CLI.new([], options).stream_passage_export
    end

    desc "documents", "One row per live document — identity, license, passage count (+ the axes with --with-axes)"
    long_desc <<~HELP, wrap: false
      Writes exports/documents.csv (or .jsonl) and documents.manifest.yml.
      One row per live (non-withdrawn) document, in urn order:

        urn, source, language, title, license_class, passage_count

      license_class is the EFFECTIVE class (a document override wins over
      its source's); passage_count counts live passages. --with-axes adds:

        lect, lect_basis      the resolved lect id and the tier that ruled it
                              (NULL basis = the bare code resolves to itself)
        script                the held text's script (the lect's ~segment)
        artifact_script       the artifact's own script where it differs
        not_before, not_after the date envelope: signed historical years,
                              BCE negative, no year 0; NULL = open/undated
        date_precision, date_class (artifact | composition | edition | silver
                              — a model/tool estimate, only where no
                              upstream date exists), date_basis
                              (the minting lane), date_raw (upstream string)
        place_name, place_ref, place_lat, place_lon
        genre, kind           facet values, sorted and |-joined

      Every axis column is NULL where that axis is absent for the document.
      The envelope is the document's primary dated row (the one `nabu show`
      renders); --from/--to keep documents whose timeline overlaps the
      window, open-ended intervals included (search's semantics).

      Examples:
        nabu export documents --with-axes
        nabu export documents --source ddbdp,edh --with-axes --format jsonl
        nabu export documents --lang lat --from -200 --to 200 --license-class open,attribution
    HELP
    table_options
    option :with_axes, type: :boolean, default: false,
                       desc: "Add the library axes: lect, script, date envelope, place, genre, kind"
    option :source, type: :string, banner: "SLUG[,SLUG...]", desc: "Restrict to these sources"
    option :lang, type: :string, banner: "CODE[,CODE...]", aliases: ["--language"],
                  desc: "Restrict to these document languages (ISO 639-1 spellings fold)"
    option :from, type: :numeric, banner: "YEAR", desc: "Timeline overlaps from this year (BCE negative)"
    option :to, type: :numeric, banner: "YEAR", desc: "Timeline overlaps up to this year"
    def documents
      with_writer("documents") do |writer, config|
        with_catalog(config) do |catalog|
          table = Nabu::Export::Documents.new(catalog: catalog, sources: list(options[:source]),
                                              langs: list(options[:lang]), from: options[:from]&.to_i,
                                              to: options[:to]&.to_i, with_axes: options[:with_axes])
          report(writer.write(table))
        end
      end
    end

    desc "links", "The links journal's edges — kind, endpoints, score, run provenance, endpoint licenses"
    long_desc <<~HELP, wrap: false
      Writes exports/links.csv (or .jsonl) and links.manifest.yml from the
      links journal (db/links.sqlite3), one row per edge in journal order:

        kind, from_urn, to_urn, score, detail,
        run_id, producer, scope, code_version        (the run provenance)
        from_source, from_license_class, to_source, to_license_class

      Endpoints resolve through the catalog at passage, document, then
      dictionary-entry grain; an endpoint the catalog no longer holds stays
      NULL (the manifest counts them). An edge draws on BOTH endpoints'
      sources: under --license-class it survives only when both classes are
      in the list. --dated adds each endpoint document's date envelope
      (from_/to_ not_before, not_after, date_class).

      Examples:
        nabu export links
        nabu export links --kind parallel,formula --dated
        nabu export links --license-class open --format jsonl
    HELP
    table_options
    option :kind, type: :string, banner: "KIND[,KIND...]", desc: "Restrict to these edge kinds"
    option :dated, type: :boolean, default: false, desc: "Add each endpoint's date envelope"
    def links
      with_writer("links") do |writer, config|
        with_catalog(config) do |catalog|
          journal = Nabu::Store::LinkLayers.open_readonly(config)
          raise Thor::Error, "export links: no links journal at #{config.links_path} — no batch producer has run" \
            unless journal

          begin
            table = Nabu::Export::Links.new(catalog: catalog, journal: journal, kinds: list(options[:kind]),
                                            dated: options[:dated])
            report(writer.write(table))
          ensure
            journal.disconnect
          end
        end
      end
    end

    desc "lemmas", "The lemma attestation matrix — lemma × language × century × grade × source counts"
    long_desc <<~HELP, wrap: false
      Writes exports/lemmas.csv (or .jsonl) and lemmas.manifest.yml from
      the precompiled lemma rollup — the same rows the `nabu lemma` desk
      reads, never a live scan. One row per cell:

        lemma, language, century, basis, grade, source,
        occurrences, documents, license_class

      lemma is the folded key; century the signed century index of the
      document envelope's midpoint (NULL = undated) with basis its date
      class; grade separates gold (upstream annotation) from silver
      (machine lemmas); occurrences counts passage attestations.

      A catalog without the rollup tables refuses with the migration
      hint; an empty rollup exports honestly and the manifest names
      `bundle exec rake builders:refresh`.

      Examples:
        nabu export lemmas --lang lat
        nabu export lemmas --lang grc,lat --grade gold --format jsonl
        nabu export lemmas --license-class open,attribution
    HELP
    table_options
    option :lang, type: :string, banner: "CODE[,CODE...]", aliases: ["--language"],
                  desc: "Restrict to these passage-language codes (as stored)"
    option :grade, type: :string, banner: "gold|silver", desc: "Restrict to one or both grades"
    def lemmas
      with_writer("lemmas") do |writer, config|
        with_catalog(config) do |catalog|
          table = Nabu::Export::Lemmas.new(catalog: catalog, langs: list(options[:lang]),
                                           grades: list(options[:grade]))
          report(writer.write(table))
        end
      end
    end

    desc "align [REF]", "Verse pairs off the alignment hub — base witness vs each other witness, per ref"
    long_desc <<~HELP, wrap: false
      Writes exports/align.jsonl (or .csv) and align.manifest.yml from the
      alignment hub (config/alignments.yml, the `nabu align` index). REF is
      `nabu align`'s grammar — a ref (MARK 2.3), a chapter (MARK 2), a range
      (MARK 2.1-2.12) or a passage urn; with no REF, --work exports the
      whole work, chapter by chapter. One row per (ref, witness): the BASE
      witness (registry's first; --base LABEL to pivot elsewhere) paired
      with every other witness attesting the ref (--witness narrows them).
      A ref the base lacks yields no pairs (counted in the manifest).

        work, ref,
        base_witness, base_document_urn, base_urns, base_covers,
        base_language, base_text, base_source, base_license_class,
        witness, witness_document_urn, witness_urns, witness_covers,
        witness_language, witness_text, witness_source, witness_license_class

      *_covers names every ref a side's sentences span (sentence≠verse).
      --with-morph adds base_/witness_ morph + tokens: the stored gold
      tokens, each {form, lemma, feats, citation} — feats DECODED into
      UD-named features through the morph façade (PROIEL/AGDT positional
      tags, UD feats, the Hebrew/Coptic tagsets), null where the source
      has none; morph is "gold" when any token carries a lemma or features.
      Token arrays need --format jsonl (the default here). A pair draws on
      both sides: under --license-class both classes must be allowed.

      Examples:
        nabu export align MARK 2 --with-morph
        nabu export align --work nt --base greek-nt --witness gothic-nt,marianus --with-morph
        nabu export align "MATT 5.1-5.12" --format csv --license-class open,attribution
    HELP
    table_options
    option :format, type: :string, default: "jsonl", banner: "jsonl|csv", desc: "Output format"
    option :work, type: :string, banner: "ID", desc: "Alignment work id (required with no REF when several exist)"
    option :base, type: :string, banner: "LABEL", desc: "The pivot witness (label or document urn)"
    option :witness, type: :string, banner: "LABEL[,LABEL...]", desc: "Pair the base only with these witnesses"
    option :with_morph, type: :boolean, default: false,
                        desc: "Add each side's gold tokens: form, lemma, decoded morphology"
    def align(*ref_parts)
      if options[:with_morph] && options[:format] == "csv"
        raise Thor::Error, "export align: --with-morph carries token arrays — use --format jsonl"
      end

      with_writer("align") do |writer, config|
        with_alignment(config) do |catalog, fulltext, registry|
          table = Nabu::Export::AlignPairs.new(catalog: catalog, fulltext: fulltext, registry: registry,
                                               ref: ref_parts.join(" "), work: options[:work],
                                               base: options[:base], witnesses: list(options[:witness]),
                                               with_morph: options[:with_morph])
          report(writer.write(table))
        end
      end
    end

    desc "collation [REF]", "The collation apparatus as rows — per anchor ref, each witness reading"
    long_desc <<~HELP, wrap: false
      Writes exports/collation.csv (or .jsonl) and collation.manifest.yml:
      the `nabu align REF --collate` apparatus, one row per witness reading.
      REF follows `nabu align` (ref, chapter, range, passage urn); with no
      REF, --work exports the whole work.

        work, ref, language, script, witness, urns, role, base_witness,
        reading, agrees, apparatus, collation, source, license_class

      Collation diffs RAW tokens inside one (language, script) cell: role is
      base or variant there, with the variant's apparatus against the base
      ("base → variant", "om. base", "add. variant"); a witness alone in its
      cell is role uncollated, collation sole or cross_script, no apparatus.
      A variant row quotes its base, so it draws on both licenses. --base
      heads every cell with that witness wherever it attests.

      Examples:
        nabu export collation MARK 2
        nabu export collation --work nt --base ccmh-marianus --format jsonl
        nabu export collation "MARK 2.1-2.12" --license-class open,attribution
    HELP
    table_options
    option :work, type: :string, banner: "ID", desc: "Alignment work id (required with no REF when several exist)"
    option :base, type: :string, banner: "LABEL", desc: "The base witness of each cell (label or document urn)"
    def collation(*ref_parts)
      with_writer("collation") do |writer, config|
        with_alignment(config) do |catalog, fulltext, registry|
          table = Nabu::Export::CollationReadings.new(catalog: catalog, fulltext: fulltext, registry: registry,
                                                      ref: ref_parts.join(" "), work: options[:work],
                                                      base: options[:base])
          report(writer.write(table))
        end
      end
    end

    # The stream's flags that only mean something with --stratum.
    STRATUM_ONLY = %i[per_cell proportional seed exclude_ocr exclude_source out license_class].freeze
    private_constant :STRATUM_ONLY

    private

    def stratified_passages
      raise Thor::Error, "export passages: --stratum takes --license-class, not --license" if options[:license]
      raise Thor::Error, "export passages: --axis does not combine with --stratum yet — use --source" if options[:axis]

      with_writer("passages") do |writer, config|
        with_catalog(config) do |catalog|
          table = Nabu::Export::PassageSample.new(
            catalog: catalog, strata: list(options[:stratum]), per_cell: options[:per_cell],
            proportional: options[:proportional], seed: options[:seed] || 0, sources: list(options[:source]),
            langs: list(options[:lang]), exclude_sources: list(options[:exclude_source]),
            exclude_ocr: options[:exclude_ocr] || false
          )
          report(writer.write(table))
        end
      end
    end

    # The alignment-hub inputs, read-only: the catalog, the full-text file
    # (the ref index lives there), the registry.
    def with_alignment(config)
      with_catalog(config) do |catalog|
        raise Thor::Error, "no full-text index — run nabu sync or nabu rebuild" unless File.exist?(config.fulltext_path)

        begin
          fulltext = Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
          yield catalog, fulltext, Nabu::AlignmentRegistry.load(config.alignments_path)
        ensure
          fulltext&.disconnect
        end
      end
    rescue Nabu::ValidationError => e
      raise Thor::Error, e.message
    end

    def list(value) = value.to_s.split(",").map(&:strip).reject(&:empty?)

    # The frame, built (and so validated) before any database opens.
    def with_writer(name)
      config = Nabu::Config.load
      classes = options[:license_class] && list(options[:license_class])
      writer = Nabu::Export::Writer.new(out_dir: File.expand_path(options[:out] || config.exports_dir),
                                        format: options[:format], license_classes: classes,
                                        progress: ->(count) { warn "  … #{count} rows" })
      yield writer, config
    rescue Nabu::Export::Error => e
      raise Thor::Error, "export #{name}: #{e.message}"
    end

    # Read-only: the exporter never writes a database.
    def with_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless File.exist?(config.catalog_path)

      catalog = Nabu::Store.connect(config.catalog_path, readonly: true)
      yield catalog
    ensure
      catalog&.disconnect
    end

    def report(result)
      say "#{result.table}: #{result.rows} rows → #{result.data_path} (in #{format_duration(result.seconds)})"
      say "  manifest → #{result.manifest_path}"
    end
  end

  class CLI < Thor
    no_commands do
      # The passage stream (P4-3), driven by `nabu export passages` (and the
      # bare `nabu export --format ...`, its default-command spelling). It
      # lives here because it shares the root's catalog/source/axis
      # helpers; ExportCLI#passages hands its options over.
      def stream_passage_export
        format = validate_format!(options[:format])
        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

        validate_source!(catalog, options[:source])
        _axis_names, axis_slugs = axis_membership(command: "export", config: config)
        lines = Nabu::Query::Export.new(catalog: catalog)
                                   .run(format: format, lang: options[:lang], license: options[:license],
                                        source: options[:source], sources: axis_slugs)
        # Stream: write each serialized line as it arrives — never join a
        # 238k-passage corpus into one string.
        lines.each { |line| $stdout.puts(line) }
      ensure
        catalog&.disconnect
      end

      # Export format gate. CoNLL-U is a first-class exit format (maintenance
      # §7) but needs the token model, so it is deferred to the enrichment
      # phase with an explicit message rather than a generic "unknown format".
      def validate_format!(format)
        raise Thor::Error, "export: --format conllu is deferred until the enrichment phase" if format == "conllu"
        return format if Nabu::Query::Export::FORMATS.include?(format)

        raise Thor::Error,
              "export: unknown format #{format.inspect} " \
              "(choose from #{Nabu::Query::Export::FORMATS.join(', ')})"
      end
    end
  end
end
