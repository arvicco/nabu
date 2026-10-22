# frozen_string_literal: true

require_relative "indexed_wikisource"

module Nabu
  module Adapters
    # The dated-Index wikisource cone (P140): the scan-indexed family
    # (IndexedWikisource) carried to wikis whose cone IS a print-year band
    # over the wiki's own scan Indexes (cy / jv / su / br). Subclasses stay
    # configuration.
    #
    # == The cone (mechanical, recomputed at every fetch)
    #
    # Every Index page of the wiki (allpages on INDEX_NS_ID) is read; an
    # Index joins the cone when its stated year (the INDEX_FIELDS "year"
    # value, else a year in the Index's own file name — "Catechis,
    # 1817.djvu") is at most LAST_PRINT_YEAR, or when it is a censused
    # EXTRA_INDEXES entry (a later print, still inside the post-1930 rule,
    # of a work composed inside the cone — each with its reason). Every
    # ns-0 page transcluding a cone Index (list=embeddedin) joins the cone,
    # provenance "index:<name>". An Index edit that moves a year re-draws
    # the cone at the next fetch — never a hand-kept list.
    #
    # == The rules (after the IndexedWikisource rules)
    #
    # after_cone — a page whose edition years (the Index years plus the
    # base statement: <pages index> names, the title's dated marks) reach
    # past LAST_PRINT_YEAR and that transcludes no EXTRA_INDEXES entry (a
    # page drawn in by one dated Index can still transclude a later one).
    # foreign_language — the MEASURED language of the rendered text: a page
    # whose share of FOREIGN_MARKERS function words reaches FOREIGN_SHARE
    # is the colonial-era scholarly apparatus (a Dutch introduction, a
    # French preface), not the text. Calibrated on real pages (census
    # 2026-10-21): running Dutch/French prose scores 13–23%, the
    # Sundanese/Javanese/Breton texts 0–2%, and a text with a Dutch
    # apparatus around it ~4.5% — the 10% line separates them.
    #
    # == Language and script
    #
    # The Index Language= value (normalized: downcased, spaces dropped)
    # must be censused (LANGUAGES — anything else quarantines loudly, the
    # gu precedent); INDEX_LECTS pins a censused Index to a different
    # code (an Old Javanese treatise on a Javanese wiki). With SCRIPTS set,
    # the script is MEASURED (the ms precedent): a non-Latin script holding
    # ≥ 80% of the letters tags the code (jav-Java), metadata "script"
    # records the measurement.
    #
    # The print year rides verbatim (source_date → MetadataDates
    # :edition_year_text, date_class edition — the print, never the
    # work's composition).
    class DatedIndexWikisource < IndexedWikisource
      INDEX_NS_ID = 106
      LAST_PRINT_YEAR = 1900
      EXTRA_INDEXES = {}.freeze
      INDEX_LECTS = {}.freeze
      LANGUAGES = {}.freeze
      SCRIPTS = {}.freeze
      SCRIPT_SHARE = 0.8
      FOREIGN_MARKERS = nil
      FOREIGN_SHARE = 0.10
      # Function-word sets for the measured foreign_language rule (words a
      # Malayo-Polynesian or Breton text does not use as running words).
      DUTCH_MARKERS = %w[de het een van en is niet zijn dat die met voor op aan te er zich worden wordt
                         deze als bij ook].to_set.freeze
      FRENCH_MARKERS = %w[le la les des et est une du que qui dans pour il pas sur ce au aux par sont
                          elle ont].to_set.freeze
      REQUIRE_EDITION_YEAR = true

      RULE_NOTES = IndexedWikisource::RULE_NOTES.merge(
        after_cone: "page(s) whose print year falls after LAST_PRINT_YEAR — outside the ruled cone " \
                    "(and no censused EXTRA_INDEXES print)",
        foreign_language: "page(s) MEASURED as foreign-language scholarly apparatus (FOREIGN_MARKERS " \
                          "share ≥ FOREIGN_SHARE)"
      ).freeze

      # -- the rules ---------------------------------------------------------

      def page_class(envelope)
        klass = envelope_class(envelope)
        return klass if klass

        passages = passages_for(envelope)
        return :empty if passages.empty?
        return :foreign_language if foreign_share(passages.map(&:text).join(" ")) >= self.class::FOREIGN_SHARE

        :text
      end

      def index_class(envelope)
        klass = super
        return klass if klass

        years = envelope_edition_years(envelope)
        return nil if years.empty? || years.max <= self.class::LAST_PRINT_YEAR
        return nil if Array(envelope["indexes"]).any? { |index| self.class::EXTRA_INDEXES.key?(index["name"]) }

        :after_cone
      end

      # The share of FOREIGN_MARKERS words among the text's words (0.0 when
      # the wiki measures nothing).
      def foreign_share(text)
        markers = self.class::FOREIGN_MARKERS or return 0.0

        words = text.downcase.scan(/\p{L}+/)
        return 0.0 if words.empty?

        words.count { |word| markers.include?(word) }.fdiv(words.size)
      end

      # Does an Index (its name + stated fields) draw its pages into the cone?
      def cone_index?(name, fields)
        return true if self.class::EXTRA_INDEXES.key?(name) || self.class::EXCLUDED_INDEXES.key?(name)

        year = fields[self.class::INDEX_FIELDS.fetch("year")]
        years = years_in(year ? display_text(year) : "")
        years = years_in(name) if years.empty?
        !years.empty? && years.max <= self.class::LAST_PRINT_YEAR
      end

      private

      # Fetch internals --------------------------------------------------------

      def cone_titles(progress)
        cone = super
        names = cone_index_names(progress)
        names.each do |name|
          embedding_titles("#{self.class::INDEX_NS}:#{name}").each { |title| cone[title] << "index:#{name}" }
        end
        progress&.call("dated Indexes: #{names.size} in the cone, #{cone.size} page(s)\n")
        cone
      end

      def cone_index_names(progress)
        names = all_index_names
        progress&.call("Indexes on the wiki: #{names.size}\n")
        fetch_indexes(names).filter_map do |name, index|
          fields = index.fetch("fields")
          in_cone = cone_index?(name, fields)
          record_index_verdict(name, year: fields[self.class::INDEX_FIELDS.fetch("year")], in_cone: in_cone)
          name if in_cone
        end.sort
      end

      # Every Index page name (namespace stripped); Index SUBPAGES (the
      # per-Index styles.css) are not Indexes.
      def all_index_names
        titles = []
        continue = {}
        loop do
          payload = get_json("action" => "query", "format" => "json", "list" => "allpages",
                             "apnamespace" => self.class::INDEX_NS_ID.to_s, "aplimit" => "500", **continue)
          titles.concat((payload.dig("query", "allpages") || []).map { |page| page.fetch("title") })
          token = payload.dig("continue", "apcontinue") or break

          continue = { "apcontinue" => token }
        end
        titles.map { |title| title.sub(/\A[^:]+:/, "") }.reject { |name| name.include?("/") }.uniq
      end

      # Language / script -------------------------------------------------------

      def language_for(envelope)
        code = index_lect(envelope) || declared_language(envelope)
        script = script_of(envelope)
        script && script != "Latn" && !script.start_with?("mixed") ? "#{code}-#{script}" : code
      end

      def index_lect(envelope)
        Array(envelope["indexes"]).filter_map { |index| self.class::INDEX_LECTS[index["name"]] }.first
      end

      def declared_language(envelope)
        declared = Array(envelope["indexes"]).map { |index| normalized_language(index_role(index, "language")) }.uniq
        codes = declared.map do |language|
          self.class::LANGUAGES.fetch(language) do
            raise ParseError, "#{envelope['title']}: Index language #{language.inspect} is not censused " \
                              "(LANGUAGES) — quarantined, never guessed"
          end
        end
        codes.first || self.class::LANGUAGES.fetch(nil)
      end

      def normalized_language(value)
        return nil if value.nil?

        normalized = value.downcase.delete(" ")
        normalized.empty? ? nil : normalized
      end

      # The measured script: the dominant SCRIPTS class (≥ SCRIPT_SHARE of
      # the letters), else "mixed: A+B"; nil when the wiki measures none.
      def script_of(envelope)
        return nil if self.class::SCRIPTS.empty?

        text = passages_for(envelope).map(&:text).join(" ")
        counts = self.class::SCRIPTS.transform_values { |pattern| text.scan(pattern).size }
                                    .select { |_, count| count.positive? }
        total = counts.values.sum
        return nil if total.zero?

        dominant, count = counts.max_by { |_, size| size }
        return dominant if count >= total * self.class::SCRIPT_SHARE

        "mixed: #{counts.sort_by { |_, size| -size }.map(&:first).join('+')}"
      end

      # Metadata ---------------------------------------------------------------

      def extra_metadata(envelope)
        {
          "source_date" => print_years(envelope),
          "index_language" => index_language(envelope),
          "script" => script_of(envelope)
        }.merge(cone_metadata(envelope)).compact
      end

      # Per-wiki additions (cy: the orthography statement); default none.
      def cone_metadata(_envelope) = {}

      def print_years(envelope)
        years = Array(envelope["indexes"]).filter_map do |index|
          year = index_role(index, "year") || index["name"][/(?<!\d)1[0-9]\d\d(?!\d)/] or next
          "#{self.class::INDEX_FIELDS.fetch('year')}: #{year} (#{index['name']})"
        end
        years.empty? ? nil : Nabu::Normalize.nfc(years.uniq.join(" · "))
      end

      def index_language(envelope)
        declared = Array(envelope["indexes"]).filter_map { |index| index_role(index, "language") }.uniq
        declared.empty? ? nil : Nabu::Normalize.nfc(declared.join(", "))
      end
    end
  end
end
