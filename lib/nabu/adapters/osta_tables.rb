# frozen_string_literal: true

require_relative "../xlsx"

module Nabu
  module Adapters
    # The OSTA works/codices tables (P77-r6, №R-30): tables/
    # tabla-obras.xlsx (2,204 work rows — the per-work language split,
    # author/title/folio, OPDT dating, the BETA cnum crosswalk) and
    # tables/tabla-codices.xlsx (594 codex rows — holding library,
    # shelfmark, SPDT copy dating, PhiloBiblon links), both indexed by
    # the HSMS siglum ("Abreviaturas HSMS" = the TEXT.<siglum> file id).
    #
    # Values ride metadata VERBATIM — the dates stay upstream text
    # ("1252 a quo", "1510 ca. ad quem"), never parsed here; the one
    # DERIVED claim is the document language, via LENGUA_CODES over the
    # works' lengua-1 values. Header-addressed columns (never
    # positional), so an upstream column shuffle is survived and a
    # renamed header fails loudly.
    class OstaTables
      OBRAS_FILE = "tabla-obras.xlsx"
      CODICES_FILE = "tabla-codices.xlsx"

      # The censused lengua vocabulary (2,204 rows, 2026-08-13:
      # castellano 2080 · gallego 39 · aragonés 32 · navarro-aragonés 18
      # · navarro 16 · castellano occidental 9 · leonés 5 · latín 4 ·
      # riojano 1) → language codes, the nearest-code discipline (the
      # IcePaHC-under-`is` precedent for medieval stages under modern
      # codes). Raw values always ride the works metadata verbatim, so
      # nothing is lost to the map.
      LENGUA_CODES = {
        "castellano" => "osp",
        "castellano occidental" => "osp", # western Castilian — the osp complex
        "riojano" => "osp",               # Riojan, conventionally within the Castilian complex
        "leonés" => "ast",                # medieval Leonese under the Asturleonese code
        "gallego" => "roa-opt",           # medieval Galician — the cantigas precedent
        "aragonés" => "arg",
        "navarro-aragonés" => "arg",      # the medieval ancestor under the modern code
        "navarro" => "arg",
        "latín" => "lat"
      }.freeze

      OBRAS_KEY = "Abreviaturas HSMS"
      CODICES_KEY = "Abreviatura HSMS"

      # nil when the tables are not in the acquisition (an older
      # canonical tree, or a workdir trimmed to the text lanes) — the
      # adapter then keeps its v1 whole-source claim.
      def self.load(dir)
        obras = File.join(dir, OBRAS_FILE)
        return nil unless File.file?(obras)

        codices = File.join(dir, CODICES_FILE)
        new(
          obras_rows: Nabu::Xlsx.rows(obras),
          codices_rows: File.file?(codices) ? Nabu::Xlsx.rows(codices) : []
        )
      end

      def initialize(obras_rows:, codices_rows:)
        @works = index_rows(obras_rows, OBRAS_KEY) { |pick| work_record(pick) }
        @codices = index_rows(codices_rows, CODICES_KEY) { |pick| codex_record(pick) }
                   .transform_values(&:first)
      end

      # The siglum's work rows in table order (a codex may hold many —
      # the cancionero shape), or nil.
      def works(siglum)
        @works[siglum]
      end

      # The siglum's codex row, or nil (not every transcription has one).
      def codex(siglum)
        @codices[siglum]
      end

      # The majority MAPPED code over the siglum's works (lengua 1 per
      # work), ties to the earliest work in table order; nil when the
      # siglum is unknown or no lengua maps.
      def language_for(siglum)
        majority(@works[siglum]) { |work| LENGUA_CODES[work["lenguas"]&.first] }
      end

      # The majority RAW lengua value — the facet surface (upstream's own
      # vocabulary, the Coptic-dialect precedent).
      def primary_lengua(siglum)
        majority(@works[siglum]) { |work| work["lenguas"]&.first }
      end

      private

      def majority(rows, &)
        values = (rows || []).filter_map(&)
        return nil if values.empty?

        values.tally.max_by { |value, count| [count, -values.index(value)] }.first
      end

      def index_rows(rows, key_header, &build)
        return {} if rows.empty?

        header = Header.new(rows.first, key: key_header)
        rows.drop(1).each_with_object({}) do |row, index|
          siglum = header.value(row, key_header) or next
          (index[siglum] ||= []) << build.call(header.picker(row))
        end
      end

      def work_record(pick)
        {
          "obra_id" => pick["Obra ID"], "hsms_id" => pick["HSMS ID"],
          "beta_manid" => pick["BETA manid"], "beta_copid" => pick["BETA copid"],
          "beta_cnum" => pick["BETA cnum"],
          "autor" => pick["Autor"], "traductor" => pick["Traductor"],
          "titulo" => pick["Título"], "folio" => pick["folio"],
          "opdt_inicio" => pick["OPDT-inicio"], "opdt_fin" => pick["OPDT-fin"],
          "lenguas" => [pick["lengua 1"], pick["lengua 2"]].compact,
          "tipo" => pick["tipo textual"],
          "materias" => (1..4).filter_map { |n| pick["materia #{n}"] },
          "num_folios" => pick["número folios"], "notas" => pick["notas"]
        }.reject { |_, value| value.nil? || value == [] }
      end

      def codex_record(pick)
        {
          "hsms_id" => pick["HSMS ID"],
          "beta_manid" => pick["BETA manid"], "beta_copid" => pick["BETA copid"],
          "biblioteca" => pick["Biblioteca"], "signatura" => pick["Signatura"],
          "spdt_inicio" => pick["SPDT-inicio"], "spdt_fin" => pick["SPDT-fin"],
          "lugar" => pick["Lugar específico de producción"],
          "productor" => pick["productor específico"],
          "formato" => pick["formato"], "num_folios" => pick["número folios"],
          "philobiblon" => pick["PhiloBiblonlink"], "facsimil" => pick["facsímildigital"],
          "subcorpus" => pick["subcorpus"], "transcriptor" => pick["transcriptor"],
          "notas" => pick["notas"]
        }.compact
      end

      # Header-name → column-index addressing; a missing KEY header is a
      # real upstream break and fails loudly, other headers resolve to
      # nil values (compacted away).
      class Header
        def initialize(row, key:)
          @indexes = {}
          row.each_with_index { |name, index| @indexes[name] = index if name }
          return if @indexes.key?(key)

          raise Nabu::Error,
                "OSTA table: expected header #{key.inspect} — got: #{row.compact.join(' | ')}"
        end

        def value(row, name)
          index = @indexes[name] or return nil
          value = row[index]
          value unless value.nil? || value.strip.empty?
        end

        def picker(row)
          ->(name) { value(row, name) }
        end
      end
    end
  end
end
