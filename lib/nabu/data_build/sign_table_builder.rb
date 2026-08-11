# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "../atf_tokenizer"
require_relative "../cdli_sign_readings"
require_relative "../sign_list"
require_relative "../adapters/asl_parser"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The sux/sign-table builder (P73-9) — the compiled per-sign card
    # table, one row per top-level OSL sign: identity (@sign name, @oid),
    # codepoints, every print-list concordance number (MZL/LAK/ABZL/...),
    # the CDLI reading concordance, and per-source attestation DOC counts
    # from the catalog — the cuneiform half of the Edubba P-1 frequency
    # rider ("true sign-counts", upgrading value-grain instruments).
    #
    # == The counting scope (stated, censused)
    #
    # Counts cover plain value tokens and bare logogram names resolved
    # against the OSL reading set (a form's reading counts under its
    # parent sign). Compound tokens (|A.BARA₂|), qualified values and
    # numbers are OUT of counting scope — censused in nabu.eval, never
    # guessed. Counted corpora: cdli / oracc / tlhdig (attribution/open);
    # the nc cuneiform lanes (etcsl, ebl) contribute NO counts — their
    # columns do not exist, so no nc contribution can hide in an integer
    # (the lemma_frequencies lesson). An absent count cell means "no
    # attestation found under this scope", never zero-by-assumption.
    class SignTableBuilder
      FILENAME = "sign-table.csv"
      COLUMNS = %w[ID Sign_Name OID Codepoints Values Lists CDLI_Readings
                   Count_cdli Count_oracc Count_tlhdig Source].freeze

      COUNT_SOURCES = %w[cdli oracc tlhdig].freeze

      CONE = "osl"
      ASL_FILE = Nabu::SignList::ASL_FILE
      BIB_KEY = "osl"

      OVERVIEW =
        "One reference row per cuneiform sign: its Oracc Sign List identity, Unicode " \
        "codepoints, the numbers every major printed sign list assigns it, the readings the " \
        "CDLI convention uses, and — the new part — how many documents of the open cuneiform " \
        "corpora actually attest it. Sign-list tooling, OCR/HTR training and teaching " \
        "instruments get identity, concordance and real-world frequency in one table."

      def initialize(canonical_dir: nil, cdli_readings: nil, registry: nil)
        @canonical_dir = canonical_dir
        @cdli_readings = cdli_readings
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "sux/sign-table needs the catalog open — attestation counts live there" if catalog.nil?

        signs = Nabu::Adapters::AslParser.new.parse_file(asl_path).signs
        value_map, name_set = reading_maps(signs)
        counts, counting_census = attestation_counts(catalog, value_map, name_set)
        rows = signs.map { |sign| card_row(sign, counts) }
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(counts),
          citations: citations,
          evaluation: { "signs" => rows.size, "counting" => counting_census },
          overview: OVERVIEW
        )
      end

      private

      def asl_path
        dir = @canonical_dir || Nabu::Config.load.canonical_dir
        path = File.join(dir, CONE, ASL_FILE)
        return path if File.file?(path)

        raise Error, "canonical input #{CONE.inspect} has no #{ASL_FILE} under " \
                     "#{File.join(dir, CONE)} — run `nabu sync osl` first"
      end

      # value string → Set of top-level sign names (a form's readings count
      # under its parent), plus the bare sign-name set for logogram hits.
      def reading_maps(signs)
        value_map = Hash.new { |hash, key| hash[key] = Set.new }
        name_set = Set.new
        signs.each do |sign|
          name_set << sign.name
          ([sign] + sign.forms).each do |record|
            record.values.reject(&:deprecated).each { |value| value_map[value.value] << sign.name }
          end
        end
        [value_map, name_set]
      end

      # {sign name => {slug => doc count}} — one streaming pass per counted
      # source, distinct-doc grain (a sign twice in one tablet counts once).
      def attestation_counts(catalog, value_map, name_set)
        tokenizer = Nabu::AtfTokenizer.new(dialect: :catf)
        counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        census = { "docs_counted" => 0, "tokens_resolved" => 0,
                   "tokens_unresolved" => 0, "tokens_out_of_scope" => 0,
                   "scope" => "value tokens and bare logogram names; compounds/qualified/" \
                              "numbers out of scope; corpora: #{COUNT_SOURCES.join('/')}" }
        COUNT_SOURCES.each do |slug|
          count_source(catalog, slug, tokenizer, value_map, name_set, counts, census)
        end
        [counts, census]
      end

      def count_source(catalog, slug, tokenizer, value_map, name_set, counts, census)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        return if source_id.nil?

        current_doc = nil
        doc_signs = nil
        flush = lambda do
          doc_signs&.each { |name| counts[name][slug] += 1 }
        end
        each_source_passage(catalog, source_id) do |row|
          if row[:document_id] != current_doc
            flush.call
            current_doc = row[:document_id]
            doc_signs = Set.new
            census["docs_counted"] += 1
          end
          scan_text(row[:text_normalized], tokenizer, value_map, name_set, doc_signs, census)
        end
        flush.call
      end

      def each_source_passage(catalog, source_id, &)
        catalog[:passages]
          .join(:documents, id: :document_id)
          .where(Sequel[:documents][:source_id] => source_id,
                 Sequel[:documents][:withdrawn] => false)
          .select(Sequel[:passages][:document_id], Sequel[:passages][:text_normalized])
          .order(Sequel[:passages][:document_id], Sequel[:passages][:sequence])
          .paged_each(&)
      end

      def scan_text(text, tokenizer, value_map, name_set, doc_signs, census)
        text.to_s.each_line do |line|
          tokens = tokenizer.tokenize_line(line) or next
          tokens.each do |token|
            unless token.kind == :value
              census["tokens_out_of_scope"] += 1
              next
            end

            names = resolve(token.value, value_map, name_set)
            if names
              names.each { |name| doc_signs << name }
              census["tokens_resolved"] += 1
            else
              census["tokens_unresolved"] += 1
            end
          end
        end
      end

      def resolve(value, value_map, name_set)
        return value_map[value] if value_map.key?(value)
        return [value] if name_set.include?(value)

        downcased = value.downcase
        value_map.key?(downcased) ? value_map[downcased] : nil
      end

      def card_row(sign, counts)
        values = sign.values.reject(&:deprecated).map(&:value)
        row = {
          "ID" => CsvWriter.mint_id("card", sign.oid || sign.name),
          "Sign_Name" => sign.name, "OID" => sign.oid,
          "Codepoints" => sign.ucun, "Values" => (values.join(";") unless values.empty?),
          "Lists" => (sign.list_numbers.join(";") unless sign.list_numbers.empty?),
          "CDLI_Readings" => cdli_readings_cell(sign), "Source" => BIB_KEY
        }
        COUNT_SOURCES.each do |slug|
          count = counts[sign.name][slug]
          row["Count_#{slug}"] = count if count.positive?
        end
        row
      end

      def cdli_readings_cell(sign)
        readings = if @cdli_readings.is_a?(Hash)
                     @cdli_readings[sign.name]
                   else
                     (@cdli_readings || default_cdli_readings)&.readings_for(sign.name)
                   end
        readings = Array(readings)
        readings.join(";") unless readings.empty?
      end

      def default_cdli_readings
        @default_cdli_readings ||= Nabu::CdliSignReadings.load_default
      end

      def resource(count)
        fields = COLUMNS.map do |name|
          { name: name, type: name.start_with?("Count_") ? "integer" : "string" }
        end
        Resource.new(name: "sign_table", path: FILENAME, rows: count,
                     fields: fields, primary_key: ["ID"])
      end

      def recipe(counts)
        digest = Digest::SHA256.hexdigest(
          counts.sort.map { |name, by_source| "#{name}:#{by_source.sort.inspect}" }.join("\x1f")
        )
        "sign-table v1: one card per top-level OSL sign (identity, codepoints, list numbers, " \
          "CDLI readings) + per-source attestation doc-counts over #{COUNT_SOURCES.join('/')} " \
          "(value/logogram tokens only, distinct-doc grain); counts sha256=#{digest}"
      end

      def citations
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        corpus = COUNT_SOURCES.filter_map do |slug|
          entry = registry[slug]
          next nil if entry.nil?

          manifest = entry.manifest
          Citation.new(key: slug, type: "misc",
                       fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                                 "note" => "license: #{manifest.license}; contributes the " \
                                           "Count_#{slug} column only" })
        end
        [osl_citation] + corpus
      end

      def osl_citation
        Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "title" => "OSL — the Oracc Sign List (ex-OGSL)",
            "author" => "Niek Veldhuis and Steve Tinney",
            "howpublished" => "https://github.com/oracc/osl",
            "note" => "CC0; sign identities, readings, codepoints, list numbers and the " \
                      "CDLI reading concordance all derive from this one repository"
          }
        )
      end
    end
  end
end
