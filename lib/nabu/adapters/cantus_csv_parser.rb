# frozen_string_literal: true

require_relative "flat_csv_parser"
require_relative "cantus_source_index"

module Nabu
  module Adapters
    # The cantus-csv family: the Cantus Database's per-source CSV export
    # (GET /source/<id>/csv/ — one row per chant record of that manuscript
    # source's inventory) read one CHANT RECORD → one document.
    #
    # The export's columns (verified 2026-11-04 on 18 exports, identical
    # header everywhere): shelfmark, holding_institution, marginalia, folio,
    # sequence, incipit, feast, service, genre, position, cantus_id, mode,
    # finalis, differentia, differentiae_database, fulltext_standardized,
    # fulltext_ms, syllabized_full_text, volpiano, image_link, melody_id,
    # addendum, extra, node_id. node_id is the chant record's own database
    # id (the /chant/<node_id>/ page) — the document's identity.
    #
    # == The full-text rule (the accepted vs skipped grain)
    #
    # A record carries the chant's text in two fields: fulltext_ms (the
    # text as the manuscript spells it — "celi", "xpictum", "{#}" for an
    # illegible/lost stretch) and fulltext_standardized (Cantus' normalized
    # spelling, from which upstream auto-generates the incipit — FAQ, "How
    # can I edit the incipit?"). Many inventories index incipits only.
    #
    #   fulltext_ms present          → accepted; the passage IS the
    #                                  manuscript text (verbatim, NFC); the
    #                                  standardized text rides annotations.
    #                                  A manuscript cue that is no longer
    #                                  than its incipit ("Alma redemptoris")
    #                                  is still what the scribe wrote.
    #   only the standardized text,  → accepted; the passage is the
    #   and it says more than the      standardized text, flagged
    #   incipit                        text_form "standardized".
    #   standardized == incipit      → SKIPPED BY RULE (:incipit_echo): the
    #   (modulo a trailing "*")        field holds no more than the incipit
    #                                  (placeholders "LACUNA", "--*" too).
    #   neither                      → SKIPPED BY RULE (:no_text).
    #
    # Every other column is mined into metadata (cantus_id — the chant's
    # Cantus Index identity, the cross-source concordance key — folio,
    # sequence, position, feast, office/genre codes with upstream's own
    # names, mode/finalis/differentia, melody id, image link, marginalia,
    # addendum, extra) and the source's metadata (siglum, institution,
    # country, centuries, provenance — CantusSourceIndex) joins every
    # record of it. The melody (volpiano) and syllabification ride passage
    # annotations beside the standardized text.
    class CantusCsvParser
      LANGUAGE = "lat"

      CHANT_URL = "https://cantusdatabase.org/chant/%<node>s/"

      REQUIRED_HEADERS = %w[folio sequence incipit feast service genre position cantus_id mode
                            fulltext_standardized fulltext_ms node_id].freeze

      # Upstream's genre abbreviations, verbatim from cantusdatabase.org/genres/
      # (read 2026-11-04; the bracketed early-index codes keyed bare).
      GENRES = {
        "?" => "Unknown, ambiguous, unidentifiable, illegible",
        "G" => "Mass chant", "GV" => "Verse for a Mass chant", "M" => "Miscellaneous",
        "MO" => "Mass Ordinary",
        "A" => "Antiphon", "Ag" => "Agnus dei", "Al" => "Alleluia", "AlV" => "Alleluia verse",
        "AV" => "Antiphon verse", "BD" => "Benedicamus domino", "Ca" => "Canticle", "Cap" => "Capitulum",
        "CaV" => "Canticle verse", "Cm" => "Communion", "CmR" => "Versus ad repetendum for the communion",
        "CmV" => "Communion verse", "Cn" => "Cantio", "CnV" => "Cantio Verse", "Co" => "Collect",
        "Cr" => "Credo", "D" => "Dramatic element", "Gl" => "Gloria", "Gr" => "Gradual",
        "GrV" => "Gradual verse", "H" => "Hymn", "HV" => "Hymn verse", "I" => "Invitatory antiphon",
        "Ig" => "Ingressa", "In" => "Introit", "InR" => "Versus ad repetendum for the introit",
        "InV" => "Introit verse", "IP" => "Invitatory psalm", "Ite" => "Ite missa est", "Ky" => "Kyrie",
        "L" => "Lesson", "Li" => "Litany", "LiV" => "Litany verse", "Of" => "Offertory",
        "OfV" => "Offertory verse", "Or" => "Oratio / Prayer", "Pc" => "Postcommunion",
        "Pn" => "Pater noster", "Pr" => "Prefatio", "PRCS" => "Preces", "PRCSV" => "Verse for the Preces",
        "PS" => "Psalm", "Psa" => "Prosa", "Psl" => "Prosula", "R" => "Responsory", "Sa" => "Sanctus",
        "Sec" => "Secret / Oratio secreta", "Sq" => "Sequence", "SqV" => "Sequence verse", "Tc" => "Tract",
        "TcV" => "Tract verse", "Tp" => "Tropus", "TpAg" => "Troped Agnus dei", "TpAl" => "Troped Alleluia",
        "TpBD" => "Troped Benedicamus domino", "TpCm" => "Troped Communion", "TpGl" => "Troped Gloria",
        "TpIn" => "Troped Introit", "TpIte" => "Troped Ite missa est", "TpKy" => "Troped Kyrie",
        "TpOf" => "Troped Offertory", "TpSa" => "Troped Sanctus", "V" => "Responsory verse",
        "Va" => "Varia", "VaHW" => "Varia within Holy Week", "W" => "Versicle"
      }.freeze

      # Upstream's service (office) abbreviations, verbatim from
      # cantusdatabase.org/services/ (read 2026-11-04).
      SERVICES = {
        "?" => "Unknown", "C" => "Compline", "CA" => "Chapter", "D" => "Day Hours",
        "E" => "Antiphons for the Magnificat or Benedictus", "H" => "Antiphons based on texts from the Historia",
        "L" => "Lauds", "M" => "Matins", "MI" => "Mass", "N" => "None", "P" => "Prime", "R" => "Memorial",
        "S" => "Sext", "T" => "Terce", "V" => "First Vespers", "V2" => "Second Vespers",
        "X" => "Supplemental, paraliturgical, rarely-used, or unclear"
      }.freeze

      # Row columns mined verbatim into metadata (blank = absent).
      VERBATIM = %w[cantus_id node_id shelfmark holding_institution folio sequence position incipit feast
                    mode finalis differentia differentiae_database melody_id marginalia addendum extra
                    image_link].freeze

      def self.present(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def self.fold_incipit(value) = value.to_s.strip.sub(/\*+\z/, "").strip.downcase

      # "manuscript" | "standardized" | nil (the full-text rule above).
      def self.text_form(row)
        return "manuscript" if present(row["fulltext_ms"])

        standardized = present(row["fulltext_standardized"])
        return nil if standardized.nil? || fold_incipit(standardized) == fold_incipit(row["incipit"])

        "standardized"
      end

      # nil for an accepted row; :no_text / :incipit_echo for the
      # skipped-by-rule incipit-only grain.
      def self.skip_reason(row)
        return nil if text_form(row)

        present(row["fulltext_standardized"]) ? :incipit_echo : :no_text
      end

      def each_row(path, &)
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS).each_row(path, &)
      end

      # One accepted chant record → its Document. +source+ is the
      # CantusSourceIndex::Source of the record's manuscript (nil when the
      # listing lacks it — the record then carries row metadata only).
      def document(row, urn:, source:, canonical_path:)
        form = self.class.text_form(row) or
          raise Nabu::ParseError, "#{canonical_path}: #{urn} carries no full text (incipit-only row)"

        metadata = row_metadata(row, form).merge(source_metadata(source))
        doc = Nabu::Document.new(urn: urn, language: LANGUAGE, canonical_path: canonical_path,
                                 title: title(row, source), metadata: metadata)
        doc << passage(row, urn, form)
      end

      private

      def nfc(value) = value && Nabu::Normalize.nfc(value)

      def passage(row, urn, form)
        manuscript = form == "manuscript"
        text = self.class.present(manuscript ? row["fulltext_ms"] : row["fulltext_standardized"])
        annotations = { "text_form" => form }
        annotations["standardized"] = nfc(self.class.present(row["fulltext_standardized"])) if manuscript
        %w[syllabized_full_text volpiano].each do |key|
          value = self.class.present(row[key])
          annotations[key] = nfc(value) if value
        end
        Nabu::Passage.new(urn: "#{urn}:1", language: LANGUAGE, text: nfc(text), sequence: 0,
                          annotations: annotations.compact)
      end

      def title(row, source)
        incipit = nfc(self.class.present(row["incipit"])) || "[no incipit]"
        where = [source&.siglum, self.class.present(row["folio"])].compact
        where.empty? ? incipit : "#{incipit} (#{nfc(where.join(', '))})"
      end

      def row_metadata(row, form)
        meta = VERBATIM.each_with_object({}) do |key, hash|
          value = self.class.present(row[key])
          hash[key] = nfc(value) if value
        end
        meta["text_form"] = form
        meta["url"] = format(CHANT_URL, node: meta["node_id"]) if meta["node_id"]
        facets = {}
        if (genre = self.class.present(row["genre"]))
          meta["genre"] = genre
          meta["genre_name"] = GENRES.fetch(genre, genre)
          facets["genre"] = { "value" => meta["genre_name"], "raw" => genre }
        end
        if (office = self.class.present(row["service"]))
          meta["office"] = office
          meta["office_name"] = SERVICES.fetch(office, office)
          facets["office"] = { "value" => meta["office_name"], "raw" => office }
        end
        facets["feast"] = meta["feast"] if meta["feast"]
        meta["facets"] = facets
        meta
      end

      # The manuscript source's axis fields, joined onto each of its
      # records: the curated century labels as the date envelope (basis
      # "source" — the witness's copying date, never the chant's
      # composition), the first place-shaped provenance as the place claim.
      def source_metadata(source)
        return {} if source.nil?

        meta = { "source_id" => source.id.to_s, "siglum" => source.siglum, "country" => source.country,
                 "institution" => source.institution }
        meta["centuries"] = source.centuries unless source.centuries.empty?
        if (date = CantusSourceIndex.date_of(source.centuries))
          meta["date"] = date.merge("basis" => "source")
        end
        meta["provenance"] = source.provenance unless source.provenance.empty?
        place = CantusSourceIndex.place_of(source.provenance)
        meta["place"] = place if place
        meta.reject { |_key, value| value.nil? || value == "" }.transform_values do |value|
          value.is_a?(String) ? nfc(value) : value
        end
      end
    end
  end
end
