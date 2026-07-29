# frozen_string_literal: true

require "digest"

require_relative "../config"
require_relative "../adapters/asl_parser"
require_relative "../adapters/osl"
require_relative "../sign_list"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The sux/value-signs builder (P53-3, Edubba ask #3): the Oracc Sign List
    # (canonical/osl/00lib/osl.asl, CC0, parsed by Adapters::AslParser)
    # flattened to ONE ROW PER (value, sign) PAIR — the table that upgrades
    # Edubba's frequency instrument from value-counts to true sign-counts —
    # plus two sidecars: signs.csv (one row per @sign/@form record) and
    # concordances.csv (the print-list numbers, MZL/LAK/ABZL/…).
    #
    # == Read path
    #
    # The canonical ASL file directly, read-only, through the same parser the
    # Nabu::SignList seam uses — NOT the catalog (osl is a feature module;
    # it has no catalog rows at all).
    #
    # == The grain and the honesty calls
    #
    # - One row per (value, sign-or-form record), depth-first in file order.
    #   A value carried by a variant @form yields the FORM's row (its own
    #   @oid and encoding) — the SignList.lookup posture. Ambiguity is
    #   VISIBLE: a value resolving to several records is several rows sharing
    #   the Value, each flagged Ambiguous=true (computed on the Value
    #   spelling across the whole table).
    # - Language scope: the slug leads sux (Sumerian — the overwhelming
    #   majority of readings and the Edubba use case); the small %-qualified
    #   minority (%akk etc.) rides Language_Qualifier, empty = the sux
    #   default. The lat/sabellic-loans precedent: the scope judgment is
    #   stated, not hidden.
    # - Deprecated values are INCLUDED and flagged (@v- → Deprecated=true):
    #   Edubba counts signs in real corpora, and texts transliterated with
    #   deprecated values exist — exclusion would silently undercount. Sign-
    #   level deprecation (@sign-) rides signs.csv.
    # - Codepoints is space-separated "U+…" hex, EMPTY when the record is
    #   honestly unencoded (~660 signs upstream); a partially encoded @useq
    #   keeps upstream's bare X/O placeholders verbatim (partial encoding is
    #   data). @upua private-use codepoints live only in signs.csv's PUA
    #   column — the PUA is not interchange-stable, so it never poses as a
    #   standard encoding.
    class ValueSignsBuilder
      CONE = Nabu::SignList::SLUG
      ASL_FILE = Nabu::SignList::ASL_FILE
      VALUES_FILENAME = "value-signs.csv"
      SIGNS_FILENAME = "signs.csv"
      CONCORDANCES_FILENAME = "concordances.csv"
      VALUES_COLUMNS = %w[ID Value Language_Qualifier Sign_Name OID Codepoints Glyph
                          Deprecated Ambiguous Source].freeze
      SIGNS_COLUMNS = %w[ID Sign_Name OID Parent_OID Aka Deprecated Codepoints PUA Glyph
                         Unicode_Name Source].freeze
      CONCORDANCES_COLUMNS = %w[ID OID Sign_Name List Number Source].freeze
      BIB_KEY = "osl"

      # The ID digest separator — the DerivationFingerprint token discipline.
      SEPARATOR = "\x1f"

      # A print-list token splits into the leading capital run (the list
      # code) and the rest (the number, suffixes verbatim: "MZL146'",
      # "RSP039^b", "ABZL239b"). A token outside that shape keeps its bytes
      # in Number with an empty List — lenient, never dropped.
      LIST_TOKEN = /\A([A-Z]+)(.+)\z/

      # Part of the derivation fingerprint: changing the derivation MUST
      # change this string.
      RECIPE = "value-signs v1: canonical/osl/00lib/osl.asl (AslParser, NFC) flattened depth-first " \
               "to one row per (value, sign-or-form record) — deprecated values INCLUDED and " \
               "flagged (real corpora are transliterated with them), %lang qualifiers split into " \
               "Language_Qualifier (empty = the sux scope the slug declares), Ambiguous = the " \
               "Value spelling resolves to more than one record; sidecars signs.csv (one row per " \
               "@sign/@form record, Parent_OID ties variants to their sign, @upua kept in PUA and " \
               "out of Codepoints) and concordances.csv (one row per print-list token, List = the " \
               "leading capital run); IDs v-<sha256(value|qualifier|oid|name)[0,12]> / s-<oid> / " \
               "c-<oid>-<token>, positional -<n> on verbatim repeats."

      NOTES = <<~NOTES.strip
        ## Language scope — sux leads, the %akk minority rides a column

        OSL serves readings for Sumerian AND Akkadian (plus a handful of other
        %-qualified languages). The slug's language call is **sux** (Sumerian):
        the overwhelming majority of values are unqualified Sumerian readings,
        and the downstream use (sign frequency over Sumerian corpora) is
        Sumerian-first. The qualified minority — ~55 `%akk` values at the
        2026-07-29 census, out of 11,238 `@v` lines — is kept, with the bare
        qualifier token (`akk`, `akk/n`, …) in `Language_Qualifier`; an empty
        cell means the default Sumerian scope. This is a stated scope
        judgment, not a claim that every unqualified reading is exclusively
        Sumerian.

        ## The grain — one row per (value, sign) pair

        A value (reading) that resolves to several signs appears once PER
        SIGN, each row flagged `Ambiguous` = `true` — ambiguity is visible as
        multiple rows sharing a `Value`, never one candidate silently. A value
        carried by a variant `@form` cites the form's own record (its `@oid`,
        its encoding), and the form's parent sign is recoverable through
        `signs.csv`'s `Parent_OID`. The primary key is the minted `ID` (values
        carry subscript digits and `ₓ`, which cannot survive the CLDF
        identifier class, so IDs are content digests); `OID` is the stable
        Oracc identifier — the interop key for joining any Oracc-side
        resource.

        ## Deprecation — included, flagged

        Deprecated values (`@v-`) are INCLUDED with `Deprecated` = `true`:
        real corpora were transliterated with them, so a frequency instrument
        that dropped them would silently undercount. Filter them out with one
        `Deprecated == "false"` clause if you want the current recommended
        readings only. Deprecated SIGNS (`@sign-`) are flagged in
        `signs.csv`; their values are not value-level deprecated unless
        themselves marked.

        ## Codepoints — absence is honest

        `Codepoints` is the space-separated Unicode scalar sequence
        (`U+122C0 U+1200A`). An EMPTY cell means the sign is honestly
        unencoded (~660 signs upstream have no encoding at all — that absence
        is data). A partially encodable compound keeps upstream's bare `X`/`O`
        placeholders verbatim inside the sequence. Private-use codepoints
        (`@upua`) appear only in `signs.csv`'s `PUA` column, never in
        `Codepoints`. `Glyph` is OSL's own rendered `@ucun` string where
        present. Booleans are the strings `true`/`false`.

        ## The sidecars

        `signs.csv` is the sign census: one row per `@sign`/`@form` record
        (forms tied to their sign by `Parent_OID`), with `Aka` aliases
        (`;`-separated), sign-level deprecation, `Unicode_Name`, and the
        encoding columns above. `concordances.csv` flattens the print-list
        numbers (`@list`): one row per (record, token), `List` = the list
        code (MZL, LAK, ABZL, …), `Number` = the rest verbatim (`127`,
        `039^b`).

        ## Loading

            import pandas as pd
            df = pd.read_csv("value-signs.csv", keep_default_na=False)
      NOTES

      def initialize(canonical_dir: Nabu::Config.load.canonical_dir)
        @canonical_dir = canonical_dir
      end

      # The builder contract: read canonical/osl read-only, write the three
      # tables into out_dir, describe the derivation. The catalog is
      # deliberately unused (osl is a feature module — no catalog rows).
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        records = flatten(Nabu::Adapters::AslParser.new.parse_file(asl_path).signs)
        counts = {
          VALUES_FILENAME => [VALUES_COLUMNS, value_rows(records)],
          SIGNS_FILENAME => [SIGNS_COLUMNS, sign_rows(records)],
          CONCORDANCES_FILENAME => [CONCORDANCES_COLUMNS, concordance_rows(records)]
        }.to_h do |filename, (columns, rows)|
          [filename, CsvWriter.write(path: File.join(out_dir, filename), columns: columns, rows: rows)]
        end
        BuildResult.new(resources: resources(counts), recipe: RECIPE, citations: citations, notes: NOTES)
      end

      private

      def asl_path
        path = File.join(@canonical_dir, CONE, ASL_FILE)
        return path if File.file?(path)

        raise Error, "canonical input #{CONE.inspect} has no #{ASL_FILE} under " \
                     "#{File.join(@canonical_dir, CONE)} — run `nabu sync osl` first"
      end

      # Depth-first, file order: each top-level sign, then its variant forms.
      # [[record, parent], ...] — parent nil for top-level signs.
      def flatten(signs)
        signs.flat_map { |sign| [[sign, nil]] + sign.forms.map { |form| [form, sign] } }
      end

      def value_rows(records)
        owners = ambiguity_census(records)
        occurrences = Hash.new(0)
        records.flat_map do |record, _parent|
          record.values.map { |value| value_row(value, record, owners, occurrences) }
        end
      end

      def value_row(value, record, owners, occurrences)
        {
          "ID" => mint_value_id(value, record, occurrences),
          "Value" => value.value,
          "Language_Qualifier" => value.language,
          "Sign_Name" => record.name,
          "OID" => record.oid,
          "Codepoints" => codepoints_cell(record),
          "Glyph" => record.ucun,
          "Deprecated" => value.deprecated.to_s,
          "Ambiguous" => (owners.fetch(value.value).size > 1).to_s,
          "Source" => BIB_KEY
        }
      end

      # Value spelling → the distinct records carrying it (object identity:
      # two records are two signs even if field-identical; each record
      # contributes once per spelling, so the owner list stays distinct).
      def ambiguity_census(records)
        owners = Hash.new { |hash, key| hash[key] = [] }
        records.each do |pair|
          record = pair.first
          record.values.map(&:value).uniq.each { |spelling| owners[spelling] << record.object_id }
        end
        owners
      end

      def sign_rows(records)
        occurrences = Hash.new(0)
        records.map do |record, parent|
          {
            "ID" => mint_sign_id(record, parent, occurrences),
            "Sign_Name" => record.name,
            "OID" => record.oid,
            "Parent_OID" => parent&.oid,
            "Aka" => (record.aka.join(";") unless record.aka.empty?),
            "Deprecated" => record.deprecated.to_s,
            "Codepoints" => codepoints_cell(record),
            "PUA" => record.upua,
            "Glyph" => record.ucun,
            "Unicode_Name" => record.uname,
            "Source" => BIB_KEY
          }
        end
      end

      def concordance_rows(records)
        occurrences = Hash.new(0)
        records.flat_map do |record, _parent|
          record.list_numbers.map do |token|
            list, number = split_token(token)
            {
              "ID" => suffixed(CsvWriter.mint_id("c", record.oid || record.name, token), occurrences),
              "OID" => record.oid,
              "Sign_Name" => record.name,
              "List" => list,
              "Number" => number,
              "Source" => BIB_KEY
            }
          end
        end
      end

      def split_token(token)
        (match = LIST_TOKEN.match(token)) ? [match[1], match[2]] : [nil, token]
      end

      # Deterministic, content-derived, ASCII (values carry subscripts and ₓ,
      # which cannot survive the CLDF identifier class): digest over the
      # value, its qualifier, and the CARRYING RECORD's identity — @oid plus
      # name, so the same-named sign+form pair the P53-1 smoke found never
      # collides. Verbatim restatements fall back to a positional suffix.
      def mint_value_id(value, record, occurrences)
        digest = Digest::SHA256.hexdigest(
          [value.value, value.language.to_s, record.oid.to_s, record.name].join(SEPARATOR)
        )[0, 12]
        suffixed("v-#{digest}", occurrences)
      end

      # The stable @oid rides the ID verbatim (it is already CLDF-safe and
      # the interop key); a record without one digests its name + parent.
      def mint_sign_id(record, parent, occurrences)
        base = record.oid ||
               Digest::SHA256.hexdigest([record.name, parent&.name.to_s].join(SEPARATOR))[0, 12]
        suffixed(CsvWriter.mint_id("s", base), occurrences)
      end

      def suffixed(id, occurrences)
        occurrence = (occurrences[id] += 1)
        occurrence > 1 ? "#{id}-#{occurrence}" : id
      end

      def codepoints_cell(record)
        record.codepoints&.join(" ")
      end

      def resources(counts)
        [[VALUES_FILENAME, "value-signs", VALUES_COLUMNS],
         [SIGNS_FILENAME, "signs", SIGNS_COLUMNS],
         [CONCORDANCES_FILENAME, "concordances", CONCORDANCES_COLUMNS]].map do |filename, name, columns|
          Resource.new(name: name, path: filename, rows: counts.fetch(filename),
                       fields: columns.map { |column| { name: column, type: "string" } },
                       primary_key: ["ID"])
        end
      end

      # OSL cited as config/sources.yml records it; the CC0 dedication
      # quoted verbatim from the osl.asl header.
      def citations
        [Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "title" => "OSL — the Oracc Sign List (ex-OGSL)",
            "author" => "Niek Veldhuis and Steve Tinney",
            "howpublished" => Nabu::Adapters::Osl::REPO_URL,
            "note" => "CC0 — \"osl.asl and its associated files are placed in the public domain " \
                      "under a CC0 licence.\" (the osl.asl header, verbatim); rolling master, " \
                      "no tags, stable @oid identifiers"
          }
        )]
      end
    end
  end
end
