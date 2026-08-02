# frozen_string_literal: true

require "json"
require "sequel"

require_relative "../errors"
require_relative "../adapters/cantigas_html_parser"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The roa-opt/cantigas builder (P56-2) — the FIRST FULL-CORPUS
    # RE-PUBLICATION: the complete Cantigas Medievais Galego-Portuguesas
    # (Littera critical edition, cantigas.fcsh.unl.pt — Lopes, Ferreira et
    # al., IEM/FCSH-NOVA) projected from the catalog into four tables. The
    # scholarly database is superb and browser-only — no TEI, no export, no
    # API — so this dataset is the corpus's first machine-readable edition,
    # published under the coordinator's written any-use grant (№45-2) with
    # the project's own citation format riding every file.
    #
    # == The tables (one edition, four projections)
    #
    # - lines.csv        one row per verse passage, numeric-cdcant catalog
    #                    order: URN + Passage_SHA256 (the urn+sha anchor),
    #                    the EDITION's line/stanza numbering, Number_Gap
    #                    where the P56-1 refrain-gap annotation fires,
    #                    Primary_Text = the verse.
    # - cantigas.csv     one row per cantiga: Cdcant (Littera's own stable
    #                    id), incipit, Author_ID → authors.csv, normalized
    #                    genre, the sidebar's formal description, rubric.
    # - authors.csv      the distinct troubadour registry (Name, Cdaut).
    # - manuscripts.csv  one row per (cantiga, manuscript witness) parsed
    #                    from the edition's "Fontes manuscritas" sigla —
    #                    the corpus-wide cancioneiro concordance.
    #
    # == The sigla grammar (live-catalog census 2026-08-02, 29 shapes over
    # 4,341 witness tokens)
    #
    # A metadata "manuscripts" entry is one sidebar line; commas separate
    # witnesses ("B 575/576, V 179"). Each witness: an optional wrapping
    # "(…)" (the edition's own notation for index-only attestations, e.g.
    # "(C 1)" — kept as Parenthesized = true), a leading capital run (the
    # cancioneiro siglum: B, V, A, C, N, T, L, P, E, TO, M censused), and
    # the rest VERBATIM as Number — "575/576" is ONE witness spanning both
    # numbers (never split), "8bis"/"517b"/"29=38"/"1146 bis" keep their
    # printed bytes, a bare siglum ("P") has an empty Number. One censused
    # line is not a witness at all: the literal "Não disponível" marker
    # (cdcant 1241) — the edition's explicit statement that no manuscript
    # source is available — yields no rows. Any other token outside this
    # grammar fails the build loudly — never guessed.
    #
    # == The eval (the citation-fidelity census)
    #
    # The edition prints a line number on every 5th verse and the parser
    # cross-checked every one at ingest (mismatch quarantines, P56-1), so
    # the ordinals here ARE the edition's: the eval counts the lines sitting
    # on those printed anchors, plus the P56-1 quirk census carried in the
    # catalog (refrain number gaps, numbered-but-empty lines, the one
    # unattributed page) — derived from the live rows at build time.
    class CantigasBuilder
      SLUG = "cantigas"
      URN_PREFIX = Nabu::Adapters::CantigasHtmlParser::URN_PREFIX

      LINES_FILENAME = "lines.csv"
      CANTIGAS_FILENAME = "cantigas.csv"
      AUTHORS_FILENAME = "authors.csv"
      MANUSCRIPTS_FILENAME = "manuscripts.csv"

      LINES_COLUMNS = %w[ID URN Passage_SHA256 Cantiga_ID Line Stanza Number_Gap Primary_Text].freeze
      CANTIGAS_COLUMNS = %w[ID Cdcant URN Incipit Author_ID Genre Form Rubric].freeze
      AUTHORS_COLUMNS = %w[ID Name Cdaut].freeze
      MANUSCRIPTS_COLUMNS = %w[ID Cantiga_ID Cancioneiro Number Parenthesized].freeze
      INTEGER_COLUMNS = %w[Line Stanza Number_Gap Cdcant Cdaut].freeze

      # The sidebar's formal-description lines join into one cell.
      FORM_SEPARATOR = "; "

      # One manuscript witness after the optional "(…)" unwrap: the leading
      # capital run is the cancioneiro siglum, the remainder (if any) rides
      # Number verbatim.
      WITNESS = /\A([A-Z]+)(?: (.+))?\z/

      # The one censused non-witness sidebar line (cdcant 1241): the
      # edition's explicit "no manuscript source available" marker — a
      # statement of absence, never a siglum row.
      NO_WITNESS_MARKER = "Não disponível"

      # The edition prints a line number every Nth verse (the parser's
      # cross-check cadence) — the eval's confirmed-ordinal census.
      PRINTED_EVERY = 5

      BIB_KEY = "littera"

      # Part of the derivation fingerprint: changing the derivation MUST
      # change this string.
      RECIPE = "roa-opt/cantigas v1: every live cantigas catalog row projected to four tables, " \
               "documents in numeric cdcant order, passages in sequence order — lines.csv one row " \
               "per verse line (URN + Passage_SHA256 anchor; Line/Stanza = the EDITION's own " \
               "numbering, cross-checked against the printed every-5th ordinals at ingest; " \
               "Number_Gap = the P56-1 refrain-gap annotation where the edition's numbering runs " \
               "ahead of the display; Primary_Text = the passage bytes); cantigas.csv one row per " \
               "cantiga (Cdcant, incipit, Author_ID -> authors.csv, normalized genre, '; '-joined " \
               "form lines, rubric; the unattributed page keeps an empty Author_ID); authors.csv " \
               "the distinct (cdaut, name) registry in cdaut order; manuscripts.csv one row per " \
               "(cantiga, witness) from the sigla lines — commas split witnesses, '(…)' becomes " \
               "Parenthesized=true, the leading capital run is Cancioneiro, the remainder is " \
               "Number VERBATIM (a slash run like 575/576 stays ONE witness; bis/letter/= forms " \
               "kept as printed; a bare siglum has an empty Number; anything else fails loudly). " \
               "IDs l-<cdcant>-<line> / c-<cdcant> / a-<cdaut> / m-<cdcant>-<siglum>-<number>, " \
               "positional -<n> on verbatim repeats."

      # The plain-language problem statement (the actib-anchors precedent):
      # a non-specialist must understand why this re-publication exists
      # before any technical section. Rendered up front by the Runner.
      OVERVIEW = <<~OVERVIEW.strip
        The cantigas are the songs of the medieval Galician-Portuguese lyric
        — the courtly cantigas de amor, the female-voiced cantigas de amigo,
        and the satirical cantigas de escárnio e maldizer, plus rarer forms
        (lais, tenções, pastorelas), composed at the Iberian courts across
        the 13th and 14th centuries. About 1,680 of them survive, by some
        160 named troubadours and jograis — kings among them — transmitted
        in three great songbooks, the cancioneiros (Ajuda, Biblioteca
        Nacional, Vaticana). This is the complete secular corpus of one of
        medieval Europe's major lyric traditions.

        The reference edition of that corpus is Cantigas Medievais Galego
        Portuguesas (cantigas.fcsh.unl.pt), the Littera project's critical
        edition by Graça Videira Lopes, Manuel Pedro Ferreira and their team
        at the Instituto de Estudos Medievais (FCSH/NOVA, Lisbon). It is a
        superb scholarly database — and it is browser-only: no TEI, no
        export, no API; every cantiga lives on a web page. Anyone wanting to
        compute over the corpus — trace an author, count refrains, join the
        songs to their manuscripts — had no machine-readable edition to
        stand on.

        This dataset is that edition: every verse line, every cantiga, every
        author and every manuscript witness, as plain tables. It exists
        because the project's coordinator granted it in writing ("Our site
        is free for all. So, with full attribution, you can do whatever you
        like with the data") — so the project's own citation format rides
        every file here, and using this data means citing the edition.

        The manuscripts table adds the piece the database never shows in one
        place: the corpus-wide concordance of which cantiga survives in
        which cancioneiro under which number — the join surface for
        manuscript-transmission questions across the whole tradition.
      OVERVIEW

      class << self
        # One witness token → [cancioneiro, number ("" when bare),
        # parenthesized?]. Public and loud: a token outside the censused
        # grammar refuses by name — drift in the edition's sigla must never
        # publish as a guessed row.
        def parse_witness(token)
          paren = token.start_with?("(") && token.end_with?(")")
          inner = paren ? token[1..-2].strip : token
          match = WITNESS.match(inner) or
            raise Error, "manuscript witness #{token.inspect} is outside the censused sigla " \
                         "grammar (optional (…), a leading capital siglum run, a verbatim " \
                         "number) — re-census before publishing"
          [match[1], match[2].to_s, paren]
        end
      end

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "roa-opt/cantigas reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        documents = document_rows(catalog)
        counts = {
          LINES_FILENAME => [LINES_COLUMNS, line_rows(documents)],
          CANTIGAS_FILENAME => [CANTIGAS_COLUMNS, cantiga_rows(documents)],
          AUTHORS_FILENAME => [AUTHORS_COLUMNS, author_rows(documents)],
          MANUSCRIPTS_FILENAME => [MANUSCRIPTS_COLUMNS, manuscript_rows(documents)]
        }.to_h do |filename, (columns, rows)|
          [filename, CsvWriter.write(path: File.join(out_dir, filename), columns: columns, rows: rows)]
        end
        census = eval_census(documents)
        BuildResult.new(resources: resources(counts), recipe: RECIPE, citations: citations,
                        overview: OVERVIEW, notes: notes(census), evaluation: census)
      end

      private

      # -- catalog reads ------------------------------------------------------

      # Every live cantigas document with its passages attached, documents
      # in NUMERIC cdcant order (string order would shuffle 97 after 1000),
      # passages in sequence order. Each document gains :cdcant/:metadata;
      # each passage :annotations.
      def document_rows(catalog)
        documents = catalog[:documents]
                    .join(:sources, id: Sequel[:documents][:source_id])
                    .where(Sequel[:documents][:withdrawn] => false, Sequel[:sources][:slug] => SLUG)
                    .select(Sequel[:documents][:id], Sequel[:documents][:urn],
                            Sequel[:documents][:title], Sequel[:documents][:metadata_json])
                    .all
        if documents.empty?
          raise Error, "the catalog has no cantigas documents — sync the corpus " \
                       "(bin/nabu sync cantigas) before building roa-opt/cantigas"
        end

        passages = catalog[:passages]
                   .where(document_id: documents.map { |row| row[:id] }, withdrawn: false)
                   .order(:document_id, :sequence)
                   .select(:document_id, :urn, :text, :content_sha256, :annotations_json)
                   .all
                   .group_by { |row| row[:document_id] }
        documents.each do |row|
          row[:cdcant] = cdcant(row[:urn])
          row[:metadata] = parse_json(row[:metadata_json], row[:urn])
          row[:passages] = (passages[row[:id]] || []).each do |passage|
            passage[:annotations] = parse_json(passage[:annotations_json], passage[:urn])
          end
        end
        documents.sort_by { |row| row[:cdcant] }
      end

      # The document's cdcant, from its urn — loud on drift (a cantigas urn
      # always carries the numeric id).
      def cdcant(urn)
        Integer(urn.delete_prefix(URN_PREFIX), 10)
      rescue ArgumentError
        raise Error, "document urn #{urn.inspect} does not carry a numeric cdcant under " \
                     "#{URN_PREFIX} — the catalog rows drifted from the cantigas identity scheme"
      end

      def parse_json(json, urn)
        JSON.parse(json.to_s)
      rescue JSON::ParserError => e
        raise Error, "#{urn}: unreadable catalog JSON (#{e.message})"
      end

      # -- the four tables ----------------------------------------------------

      def line_rows(documents)
        documents.flat_map do |doc|
          doc[:passages].map do |passage|
            annotations = passage[:annotations]
            {
              "ID" => CsvWriter.mint_id("l", doc[:cdcant], annotations.fetch("line")),
              "URN" => passage[:urn],
              "Passage_SHA256" => passage[:content_sha256],
              "Cantiga_ID" => cantiga_id(doc),
              "Line" => annotations.fetch("line"),
              "Stanza" => annotations.fetch("stanza"),
              "Number_Gap" => annotations["number_gap"],
              "Primary_Text" => passage[:text]
            }
          end
        end
      end

      def cantiga_rows(documents)
        documents.map do |doc|
          metadata = doc[:metadata]
          {
            "ID" => cantiga_id(doc),
            "Cdcant" => doc[:cdcant],
            "URN" => doc[:urn],
            "Incipit" => doc[:title],
            "Author_ID" => author_id(doc),
            "Genre" => metadata["genre"],
            "Form" => (Array(metadata["form"]).join(FORM_SEPARATOR) if metadata["form"]),
            "Rubric" => metadata["rubric"]
          }
        end
      end

      # "a-<cdaut>", empty on the censused unattributed page shape — any
      # other author-less document is metadata drift, loud.
      def author_id(doc)
        cdaut = doc[:metadata]["author_id"]
        return CsvWriter.mint_id("a", cdaut) unless cdaut.nil?
        return nil if doc[:metadata]["unattributed"]

        raise Error, "#{doc[:urn]}: no author_id and no unattributed flag — the document " \
                     "metadata drifted from the parser contract"
      end

      # The distinct (cdaut, name) registry, numeric cdaut order. A cdaut
      # carrying two spellings would be an upstream inconsistency worth
      # refusing over (zero at the 2026-08-02 census), never silently folded.
      def author_rows(documents)
        authors = {}
        documents.each do |doc|
          cdaut = doc[:metadata]["author_id"] or next
          name = doc[:metadata]["author"]
          if authors.key?(cdaut) && authors[cdaut] != name
            raise Error, "cdaut #{cdaut} carries two name spellings (#{authors[cdaut].inspect} vs " \
                         "#{name.inspect}) — refuse and re-census rather than pick one"
          end
          authors[cdaut] = name
        end
        authors.sort.map do |cdaut, name|
          { "ID" => CsvWriter.mint_id("a", cdaut), "Name" => name, "Cdaut" => cdaut }
        end
      end

      def manuscript_rows(documents)
        occurrences = Hash.new(0)
        documents.flat_map do |doc|
          Array(doc[:metadata]["manuscripts"]).flat_map do |line|
            next [] if line == NO_WITNESS_MARKER

            line.split(",").map(&:strip).map do |token|
              siglum, number, paren = self.class.parse_witness(token)
              {
                "ID" => suffixed(mint_witness_id(doc, siglum, number), occurrences),
                "Cantiga_ID" => cantiga_id(doc),
                "Cancioneiro" => siglum,
                "Number" => number,
                "Parenthesized" => paren.to_s
              }
            end
          end
        end
      end

      def cantiga_id(doc)
        CsvWriter.mint_id("c", doc[:cdcant])
      end

      # "m-600-B-575-576"; a bare siglum mints without a number segment.
      def mint_witness_id(doc, siglum, number)
        components = ["m", doc[:cdcant], siglum]
        components << number unless number.empty?
        CsvWriter.mint_id(*components)
      end

      def suffixed(id, occurrences)
        occurrence = (occurrences[id] += 1)
        occurrence > 1 ? "#{id}-#{occurrence}" : id
      end

      # -- the eval -----------------------------------------------------------

      # The citation-fidelity census, from the catalog's annotations: the
      # edition's printed every-5th ordinals were each verified at ingest
      # (or resynced across a censused refrain gap — P56-1), so counting
      # the lines on that cadence counts the printed confirmations.
      def eval_census(documents)
        lines = documents.sum { |doc| doc[:passages].size }
        confirmed = documents.sum do |doc|
          doc[:passages].count { |passage| (passage[:annotations].fetch("line") % PRINTED_EVERY).zero? }
        end
        gap_lines = documents.sum do |doc|
          doc[:passages].count { |passage| passage[:annotations].key?("number_gap") }
        end
        {
          "documents" => documents.size,
          "lines" => lines,
          "printed_number_confirmed" => confirmed,
          "number_gap_lines" => gap_lines,
          "number_gap_total" => documents.sum { |doc| doc[:metadata]["number_gaps"].to_i },
          "empty_lines" => documents.sum { |doc| Array(doc[:metadata]["empty_lines"]).size },
          "unattributed" => documents.count { |doc| doc[:metadata]["unattributed"] },
          "against" => "the Littera edition's own printed line numbers (one every 5th verse): the " \
                       "parser cross-checked every printed ordinal at ingest and quarantined any " \
                       "mid-stanza drift (P56-1), so the counted lines sit on verified anchors; " \
                       "number_gap/empty_lines/unattributed carry the P56-1 quirk census from the " \
                       "catalog metadata, re-derived at build time"
        }
      end

      # -- furniture ----------------------------------------------------------

      def csv_fields(columns)
        columns.map { |name| { name: name, type: INTEGER_COLUMNS.include?(name) ? "integer" : "string" } }
      end

      def resources(counts)
        [[LINES_FILENAME, "lines", LINES_COLUMNS],
         [CANTIGAS_FILENAME, "cantigas", CANTIGAS_COLUMNS],
         [AUTHORS_FILENAME, "authors", AUTHORS_COLUMNS],
         [MANUSCRIPTS_FILENAME, "manuscripts", MANUSCRIPTS_COLUMNS]].map do |filename, name, columns|
          Resource.new(name: name, path: filename, rows: counts.fetch(filename),
                       fields: csv_fields(columns), primary_key: ["ID"])
        end
      end

      # The project's own citation format rides verbatim — the grant's one
      # condition (№45-2). Referenced lazily so the builder file stays
      # loadable without the adapter graph.
      def citation_format
        Nabu::Adapters::Cantigas::CITATION
      end

      def citations
        [Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "author" => "Lopes, Graça Videira and Ferreira, Manuel Pedro and others",
            "title" => "Cantigas Medievais Galego Portuguesas [online database]",
            "year" => "2011--",
            "publisher" => "Instituto de Estudos Medievais, FCSH/NOVA",
            "address" => "Lisboa",
            "howpublished" => "https://cantigas.fcsh.unl.pt",
            "note" => "Free with attribution — the coordinator's written grant (Graça Videira " \
                      "Lopes, 2026-07-27, №45-2): \"Our site is free for all. So, with full " \
                      "attribution, you can do whatever you like with the data.\" The project's " \
                      "own citation format: #{citation_format}"
          }
        )]
      end

      def notes(census)
        <<~NOTES.strip
          ## The tables — one edition, four projections

          `lines.csv` is the corpus at verse grain, in cdcant order: `URN` +
          `Passage_SHA256` name the exact catalog passage bytes (rows apply
          only where the sha matches — the urn+sha anchoring contract);
          `Line`/`Stanza` are the EDITION's own numbering (see the census
          below); `Number_Gap` is non-empty exactly where the edition's
          numbering runs ahead of the displayed text (refrain lines the page
          display merges — the value is how many edition lines the display
          skipped, riding the stanza's first line); `Primary_Text` is the
          verse. `cantigas.csv` is one row per cantiga: `Cdcant` is Littera's
          own stable id (the `cdcant=` URL parameter), `Incipit` the first
          verse, `Author_ID` joins `authors.csv` (empty on the one
          unattributed page), `Genre` the normalized genre facet, `Form` the
          sidebar's formal description (`; `-joined), `Rubric` the
          manuscript rubric where one exists. `authors.csv` is the distinct
          troubadour/jogral registry with Littera's `Cdaut` ids. Join
          `lines.Cantiga_ID` and `manuscripts.Cantiga_ID` on `cantigas.ID`.

          ## manuscripts.csv — the cancioneiro concordance

          One row per (cantiga, manuscript witness), parsed from the
          edition's *Fontes manuscritas* sigla lines. Comma-separated
          witnesses become rows; the leading capital run is the
          `Cancioneiro` siglum (A = Cancioneiro da Ajuda, B = Biblioteca
          Nacional, V = Vaticana, C = the Tavola Colocciana index, plus the
          edition's smaller sigla — N, T, L, P, E, TO, M at this census);
          everything after it rides `Number` VERBATIM: a slash run
          (`575/576`) is ONE witness spanning those numbers, never split;
          `8bis`, `517b`, `29=38` and `1146 bis` keep their printed bytes; a
          bare siglum (`P`) has an empty `Number`. A witness the edition
          prints in parentheses (`(C 1)` — an index attestation, not a text
          witness) keeps `Parenthesized` = `true`. One sidebar line is not a
          witness at all: the literal "Não disponível" marker (the edition's
          explicit statement that no manuscript source is available — one
          cantiga at this census) yields no rows, and a cantiga whose page
          carries no *Fontes manuscritas* section likewise has none. Any
          other token outside this grammar fails the build loudly — the
          concordance never guesses.

          ## The citation — the grant's one condition

          This corpus is published with the written permission of the
          project's coordinator (Graça Videira Lopes, 2026-07-27, license
          thread №45-2): "Our site is free for all. So, with full
          attribution, you can do whatever you like with the data." Use of
          this dataset therefore carries the project's own citation format,
          verbatim (fill the retrieval-date slot with the date you took this
          dataset):

          > #{citation_format}

          ## The census — citation fidelity (`nabu.eval`)

          Of #{census.fetch('lines')} verse lines across #{census.fetch('documents')} cantigas:
          #{census.fetch('printed_number_confirmed')} sit on the edition's printed every-5th
          ordinals — each one verified against the printed number at ingest
          (a mismatch quarantines the page, so the `Line` column IS the
          edition's numbering); #{census.fetch('number_gap_lines')} lines open a refrain
          number gap (#{census.fetch('number_gap_total')} edition lines counted but not displayed
          upstream — the `Number_Gap` column); #{census.fetch('empty_lines')} edition line numbers
          are consumed by numbered-but-textless rows upstream (censused in
          the eval, no row minted); #{census.fetch('unattributed')} cantiga(s) carry no author
          attribution. The same numbers ride `datapackage.json` under
          `nabu.eval`.

          ## The honest gap — cdcant 1066

          One cantiga of the corpus, cdcant 1066, has no text in the edition
          ("Texto ainda não disponível" — a doubled apógrafo transcription
          Littera has not yet published). It is quarantined at ingest and
          appears in NO table here; when the edition publishes the text, a
          re-sync and re-build will pick it up.

          ## Loading

              import pandas as pd
              lines = pd.read_csv("lines.csv", keep_default_na=False)
              cantigas = pd.read_csv("cantigas.csv", keep_default_na=False)
              corpus = lines.merge(cantigas, left_on="Cantiga_ID", right_on="ID",
                                   suffixes=("", "_cantiga"))

          How to cite: the Littera citation above (the `littera` key in
          `sources.bib`) alongside this dataset's `datapackage.json`
          provenance block.
        NOTES
      end
    end
  end
end
