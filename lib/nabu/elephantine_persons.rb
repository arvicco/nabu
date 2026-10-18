# frozen_string_literal: true

require "nokogiri"

require_relative "normalize"

module Nabu
  # The Elephantine ancient-persons read seam: the project's prosopography
  # authority (elephantine_erc_db_ancient_persons.tei.xml, fetched with the
  # record crawl into canonical/elephantine) projected into the
  # "elephantine" Store::PersonIndex slice — the CbdbPersons mold, driven
  # from the same adapter hook at sync and rebuild.
  #
  # == The authority (censused whole, 2026-10-18)
  #
  # particDesc/listPerson holds 7,577 <person> records: 7,457 under
  # listPerson[@type="historical"] (ids p<N>) and 120 under
  # [@type="mythological"] (deities, ids d<N> — kept: the records
  # reference them like persons, and the id prefix keeps them apart).
  # Each carries:
  #   <sex value="0|1|2">  not known / male / female (7,204; absent on 373)
  #   <persName xml:lang="en">  the English display form — on EVERY record
  #   <persName xml:lang="egy|grc|arc|cop|…">  the original-language form
  #     (exactly one on 7,560 records; untagged on deities and a few
  #     others; @type="epithet" forms on deities), 2,712 forms carrying
  #     @ref = a Trismegistos NAME record URL
  #   <link target="…trismegistos.org/per/detail.php?pnr=N">  the TM
  #     PERSON link (2,687 records)
  # A trailing listRelation (1,327 parent + 29 spouse edges, many to TM
  # persons outside the authority) is NOT projected: the person index has
  # no kinship lane — deliberate, declared scope.
  #
  # == Projection onto the Person shape
  #
  # name = the English form; name_han = the first original-language form
  # (non-en/de, non-epithet — the native-form lane, see PersonIndex);
  # female = sex value 2; refs = the TM person link, then the TM name
  # record(s), verbatim URLs space-joined (whitespace inside a URL — one
  # censused "pnr= N" — is squeezed out); every name form, epithets
  # included, keys under the shared fold. The authority file carries no
  # dates (birth/death/index years and dynasty stay nil) and no licence
  # element of its own; the project's per-record grant (CC BY-SA 3.0)
  # covers the export, and nothing derived here is exported.
  module ElephantinePersons
    AUTHORITY = "elephantine"
    FILENAME = "elephantine_erc_db_ancient_persons.tei.xml"

    # The original-language forms never chosen as the native name.
    DISPLAY_LANGS = %w[en de].freeze
    FEMALE = "2"

    Census = Data.define(:persons, :seconds)

    module_function

    def authority_path(workdir)
      path = File.join(workdir, FILENAME)
      File.file?(path) ? path : nil
    end

    # Stream every <person> as a Store::PersonIndex::Person (DOM: the
    # authority is ~2 MB, well under the Reader threshold).
    def each_person(path, &)
      return enum_for(:each_person, path) unless block_given?

      doc = Nokogiri::XML(File.read(path))
      doc.remove_namespaces!
      doc.xpath("//particDesc//listPerson/person").each { |node| yield build_person(node) }
    end

    def build_person(node)
      forms = node.xpath("persName")
      english = text_of(forms.find { |form| form["lang"] == "en" })
      Store::PersonIndex::Person.new(
        authority: AUTHORITY, person_id: node["id"].to_s,
        name: english, name_han: native_form(forms),
        birth_year: nil, death_year: nil, index_year: nil,
        dynasty: nil, dynasty_han: nil,
        female: node.at_xpath("sex")&.[]("value") == FEMALE,
        name_keys: forms.filter_map { |form| text_of(form) }.map { |n| Nabu::Pleiades.name_key(n) }.uniq,
        refs: refs_of(node, forms)
      )
    end

    def native_form(forms)
      form = forms.find { |f| !DISPLAY_LANGS.include?(f["lang"]) && f["type"].nil? }
      text_of(form)
    end

    def refs_of(node, forms)
      urls = node.xpath("link/@target").map(&:value) + forms.filter_map { |form| form["ref"] }
      urls = urls.map { |url| url.gsub(/\s+/, "") }.reject(&:empty?).uniq
      urls.empty? ? nil : urls.join(" ")
    end

    def text_of(node)
      return nil if node.nil?

      text = node.text.gsub(/[[:space:]]+/, " ").strip
      text.empty? ? nil : Normalize.nfc(text)
    end

    # The sync/rebuild derivation seam (the CbdbPersons::Producer mold):
    # the elephantine person-index slice, wholesale. No authority file →
    # honest no-op.
    class Producer
      def initialize(catalog:)
        @catalog = catalog
      end

      def authority = AUTHORITY

      def run(_slug, workdir:)
        path = ElephantinePersons.authority_path(workdir)
        return nil if path.nil?

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count = Store::PersonIndex.derive!(
          @catalog, persons: ElephantinePersons.each_person(path), authority: AUTHORITY
        )
        return nil if count.nil?

        Census.new(persons: count,
                   seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end
  end
end
