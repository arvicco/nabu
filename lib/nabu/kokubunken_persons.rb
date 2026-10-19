# frozen_string_literal: true

require "nokogiri"

require_relative "normalize"

module Nabu
  # The kokubunken personography read seam: the <listPerson> records each
  # NIJL TEI file carries in its <back> (every xml:id a poem or colophon
  # points at through persName/@corresp, l/@resp or div/@corresp)
  # projected into the "kokubunken" Store::PersonIndex slice — the
  # ElephantinePersons mold, driven from the adapter hook at sync and
  # rebuild.
  #
  # == The authority (censused whole, 2026-10-18)
  #
  # 326 <person> records over the three files, 266 distinct ids:
  #   古今和歌集 (194): sex (1 male 104 · 2 female 28 · 3 on 2 · absent 60),
  #     persName forms — the "藤原／定家" surname／given split, readings
  #     (untyped or type="よみ"), aliases (京極中納言, 明静) — birth/death
  #     with @when years (34/62; "不明" prose without @when otherwise),
  #     idno VIAF (38 URLs; "ナシ" or empty elsewhere) and 国書データベース
  #     (40 bare NIJL ids, no URL in the file — not carried as refs).
  #   廣瀬本 / 元暦校本 万葉集 (73 + 59, the latter a subset): <name>-only
  #     records (one with a second name).
  # The ids ARE names (xml:id="藤原定家"); a record recurring across files
  # under one id merges (name forms unioned, the first stated date/sex/
  # link kept) — one shared id string is upstream's own identity claim.
  #
  # == Projection onto the Person shape
  #
  # name = name_han = the first form with the ／ split dropped (the forms
  # are native script; there is no separate transcription); every form
  # keys both joined and ／→space split; birth/death years from @when
  # (zero-padded "0825" → 825); female = sex 2 (sex 1 → false; 3 or
  # absent → nil, unknown); refs = the VIAF URLs, verbatim.
  module KokubunkenPersons
    AUTHORITY = "kokubunken"
    SPLIT = "／"
    WHEN_YEAR = /\A(-?\d{1,4})/

    Census = Data.define(:persons, :seconds)

    module_function

    # Every person across the adapter's TEI files under +workdir+ (file
    # order, then document order), merged by id.
    def each_person(workdir, &)
      return enum_for(:each_person, workdir) unless block_given?

      merged = {}
      tei_paths(workdir).each do |path|
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
        doc.remove_namespaces!
        doc.xpath("//listPerson/person[@id]").each do |node|
          record = read_record(node)
          merged[record[:id]] = merged.key?(record[:id]) ? merge(merged[record[:id]], record) : record
        end
      end
      merged.each_value { |record| yield build_person(record) }
    end

    def tei_paths(workdir)
      Adapters::Kokubunken::FILES.values.map { |spec| File.join(workdir, spec[:name]) }.select { |p| File.file?(p) }
    end

    def read_record(node)
      {
        id: node["id"].to_s.strip,
        forms: node.xpath("persName | name").filter_map { |form| text_of(form) },
        birth: year_of(node.at_xpath("birth")),
        death: year_of(node.at_xpath("death")),
        female: { "1" => false, "2" => true }[node["sex"].to_s.strip],
        refs: node.xpath("idno").map { |idno| idno.text.strip }.grep(%r{\Ahttps?://})
      }
    end

    def merge(first, later)
      first.merge(forms: (first[:forms] + later[:forms]).uniq,
                  birth: first[:birth] || later[:birth], death: first[:death] || later[:death],
                  female: first[:female].nil? ? later[:female] : first[:female],
                  refs: (first[:refs] + later[:refs]).uniq)
    end

    def build_person(record)
      primary = record[:forms].first&.delete(SPLIT) || record[:id]
      keys = record[:forms].flat_map { |form| [form.delete(SPLIT), form.tr(SPLIT, " ")] } + [record[:id]]
      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: record[:id],
        name: primary, name_han: primary,
        birth_year: record[:birth], death_year: record[:death], index_year: nil,
        dynasty: nil, dynasty_han: nil, female: record[:female],
        name_keys: keys.map { |form| Nabu::Pleiades.name_key(form) }.uniq,
        refs: record[:refs].empty? ? nil : record[:refs].join(" ")
      )
    end

    def year_of(node)
      match = WHEN_YEAR.match(node&.[]("when").to_s) or return nil

      year = Integer(match[1], 10)
      year.zero? ? nil : year
    end

    def text_of(node)
      text = node.text.gsub(/[[:space:]]+/, "")
      text.empty? ? nil : Normalize.nfc(text)
    end

    # The sync/rebuild derivation seam (the ElephantinePersons::Producer
    # mold): the kokubunken person-index slice, wholesale. No TEI files →
    # honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def authority = AUTHORITY

      def run(_slug, workdir:)
        return nil if KokubunkenPersons.tei_paths(workdir).empty?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PersonIndex.derive!(
          @catalog, persons: KokubunkenPersons.each_person(workdir), authority: AUTHORITY
        )
        return nil if count.nil?

        Census.new(persons: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
