# frozen_string_literal: true

require "nokogiri"
require_relative "adapters/e84000"

module Nabu
  # The 84000 → Derge title crosswalk (P106-5 — the e84000 sidecar lode 2):
  # the derge shelves mint their ~4.5k documents from {D…} markers alone,
  # title-less; every 84000 header — placeholder stubs (3,926: the titles
  # of every UNTRANSLATED text) and published translations alike — carries
  # its text's English and Tibetan (Wylie) mainTitles keyed by the same
  # Toh numbers the derge slugs use. This pass reads the headers off
  # canonical/e84000 and fills documents.title on the matching derge rows.
  #
  # The join is EXACT-KEY only: bibl key "toh846a" titles derge toh846a,
  # a part key (toh1-1) titles the part document — no base-container
  # inference, ever (a container's title must come from a bare-base key).
  # Published titles win over placeholder titles for the same key (the
  # published header is the curated one); published files resolve
  # duplicate pairs through the primary adapter's own winner rule, so
  # this pass can never disagree with the passage shelf about editions.
  #
  # Derived by construction: f(canonical/e84000 + loaded derge rows) —
  # documents.title on these shelves is NULL from the loader, the pass
  # re-fills idempotently, and it re-runs at rebuild, in the builder
  # refresh, and after e84000/derge syncs (no lane may lag a sync).
  # An absent e84000 tree is a clean no-op (a clone without the source).
  class E84000DergeTitles
    E84000_SLUG = "e84000"
    # Collection directory → the derge shelf its Toh keys title.
    SHELF_PREFIXES = {
      "kangyur" => "urn:nabu:derge-kangyur:",
      "tengyur" => "urn:nabu:derge-tengyur:"
    }.freeze
    # A bibl's location/@work → the shelf its key titles (#shelf_of).
    WORK_SHELVES = {
      "UT4CZ5369" => SHELF_PREFIXES.fetch("kangyur"),
      "UT23703" => SHELF_PREFIXES.fetch("tengyur")
    }.freeze
    HEADER_END = "</teiHeader>"
    HEADER_CHUNK = 1 << 16
    # Wylie titles close with the shad rendered "/" — a display title
    # drops it (key_raw-style verbatim keeping is the glossary lane's
    # business; this is our own minted display field).
    TRAILING_SLASH = %r{[\s/]+\z}

    # == The persons half (same headers, same exact-key join)
    #
    # Each header's sourceDesc bibl also names its text's persons — census
    # 2026-10-18 over all 4,322 headers: 5,072 role="translatorTib" (the
    # Tibetan-era translators), 3,385 role-less <author>s (the original
    # author — 676 distinct, "Anon" 755 times: upstream's own claim, carried
    # verbatim and faceted like any name) and 66 role="authorContested"
    # (disputed attributions), on 3,657 keyed bibls. Per matching derge
    # document the pass merges into documents.metadata_json:
    #   "persons" [{"name", "role" (verbatim; the role-less author as
    #     "author"), "lang" (xml:lang: Sa-Ltn / Bo-Ltn)}],
    #   "authors" / "authors_contested" / "translators_tib" (flat names);
    # every other metadata key is the loader's and is left untouched. A
    # later tier's header replaces a key's whole person list (published
    # over placeholder, the titles rule). Names ride verbatim, whitespace
    # collapsed (one published name carries a soft hyphen — kept, the
    # canonical-means-canonical rule the parser applies to its titles).
    #
    # Facets: the facet builders run BEFORE this pass in every flow, so the
    # pass writes its documents' author / author_contested / translator
    # rows itself (delete-then-insert, those three facets only);
    # config/facet_map.yml declares the same projection, so any later facet
    # refresh of a derge shelf re-derives identical rows from the merged
    # metadata. Trade-off, declared: a derge re-parse rewrites
    # metadata_json to the adapter's own keys (no revision bump — the
    # loader's metadata reconcile), and this pass, which runs after every
    # derge sync, merges the persons back.
    PERSON_KEYS = %w[persons authors authors_contested translators_tib].freeze
    ROLE_FIELDS = {
      Adapters::E84000TeiParser::ORIGINAL_AUTHOR_ROLE => %w[authors author],
      "authorContested" => %w[authors_contested author_contested],
      "translatorTib" => %w[translators_tib translator]
    }.freeze
    OWNED_FACETS = ROLE_FIELDS.values.map(&:last).freeze

    Result = Data.define(:titled, :missing_docs, :files, :persons)

    def initialize(catalog:, canonical_dir:)
      @catalog = catalog
      @canonical_dir = canonical_dir
    end

    def run
      titles, persons = crosswalk
      return Result.new(titled: 0, missing_docs: 0, files: 0, persons: 0) if titles.empty? && persons.empty?

      titled = 0
      missing = 0
      with_persons = 0
      @catalog.transaction do
        titles.each do |(prefix, key), title|
          updated = @catalog[:documents].where(urn: "#{prefix}#{key}").update(title: title)
          updated.positive? ? titled += updated : missing += 1
        end
        with_persons = merge_persons(persons)
      end
      Result.new(titled: titled, missing_docs: missing, files: @files, persons: with_persons)
    end

    private

    # [{[shelf urn prefix, toh key] => display title},
    #  {[shelf urn prefix, toh key] => [person, …]}] over every 84000
    # header. Placeholders first, then published (hash overwrite = the
    # published-wins rule); files sorted for determinism within each tier.
    def crosswalk
      @files = 0
      workdir = File.join(@canonical_dir, E84000_SLUG)
      return [{}, {}] unless Dir.exist?(workdir)

      titles = {}
      persons = {}
      placeholder_files(workdir).each { |path, prefix| harvest(path, prefix, titles, persons) }
      published_files(workdir).each { |path, prefix| harvest(path, prefix, titles, persons) }
      [titles, persons]
    end

    # Rewrite every derge document's derived person keys from +persons+
    # (absent → the keys are removed: a claim no header makes any more
    # never lingers) and re-insert its owned facet rows. Returns the
    # number of documents carrying persons.
    def merge_persons(persons)
      with_persons = 0
      SHELF_PREFIXES.each_value do |prefix|
        docs = @catalog[:documents].where(Sequel.like(:urn, "#{prefix}%")).select_map(%i[id urn metadata_json])
        next if docs.empty?

        @catalog[:document_facets].where(document_id: docs.map(&:first), facet: OWNED_FACETS).delete
        docs.each do |id, urn, json|
          list = persons[[prefix, urn.delete_prefix(prefix)]] || []
          with_persons += 1 unless list.empty?
          write_persons(id, json, list)
        end
      end
      with_persons
    end

    def write_persons(id, json, list)
      metadata = json.nil? ? {} : JSON.parse(json)
      fields = person_fields(list)
      merged = metadata.except(*PERSON_KEYS).merge(fields)
      canonical = Store::ContentHash.canonical_json(merged)
      @catalog[:documents].where(id: id).update(metadata_json: canonical) unless canonical == json
      ROLE_FIELDS.each_value do |field, facet|
        Array(fields[field]).each do |name|
          @catalog[:document_facets].insert(document_id: id, facet: facet, value: name, raw: nil)
        end
      end
    end

    def person_fields(list)
      return {} if list.empty?

      fields = { "persons" => list }
      ROLE_FIELDS.each do |role, (field, _facet)|
        names = list.select { |person| person["role"] == role }.map { |person| person["name"] }.uniq
        fields[field] = names unless names.empty?
      end
      fields
    end

    def placeholder_files(workdir)
      SHELF_PREFIXES.flat_map do |collection, prefix|
        Dir.glob(File.join(workdir, "translations", collection, "placeholders", "*.xml"))
           .map { |path| [path, prefix] }
      end
    end

    # The primary adapter's discover carries the collection in ref
    # metadata and has already applied the duplicate-pair winner rule.
    def published_files(workdir)
      Adapters::E84000.new.discover(workdir).filter_map do |ref|
        prefix = SHELF_PREFIXES[ref.metadata["collection"]]
        [ref.path, prefix] if prefix
      end
    end

    def harvest(path, prefix, titles, persons)
      header = header_slice(path) or return
      doc = Nokogiri::XML(header, &:recover)
      harvest_persons(doc, prefix, persons)
      title = display_title(doc) or return

      @files += 1
      doc.xpath("//*[local-name()='bibl'][@type='text']").each do |bibl|
        value = bibl["key"].to_s.strip
        titles[[shelf_of(bibl, prefix), value]] = title unless value.empty?
      end
    end

    # Every keyed sourceDesc bibl's <author> children, per key (a bibl
    # naming none still records the empty list — a later tier's silence
    # replaces an earlier tier's claim, the titles overwrite rule).
    def harvest_persons(doc, prefix, persons)
      doc.xpath("//*[local-name()='sourceDesc']/*[local-name()='bibl'][@key]").each do |bibl|
        key = bibl["key"].to_s.strip
        next if key.empty?

        persons[[shelf_of(bibl, prefix), key]] =
          bibl.xpath("./*[local-name()='author']").filter_map { |author| person_of(author) }
      end
    end

    # The shelf a bibl's Toh key lives on: the bibl's OWN location/@work
    # (UT4CZ5369 the Degé Kangyur, UT23703 the Degé Tengyur — 4,603 of
    # 4,631 keyed bibls state one) over the file's collection directory —
    # 22 bibls in Kangyur publications/placeholders key Tengyur texts
    # (toh326's commentary toh4099, the multi-Toh toh471,2006 …).
    def shelf_of(bibl, fallback)
      work = bibl.at_xpath("./*[local-name()='location']")&.[]("work")
      WORK_SHELVES.fetch(work, fallback)
    end

    def person_of(author)
      name = author.text.gsub(/[[:space:]]+/, " ").strip
      return nil if name.empty?

      { "name" => Normalize.nfc(name),
        "role" => author["role"] || Adapters::E84000TeiParser::ORIGINAL_AUTHOR_ROLE,
        "lang" => author.attribute_with_ns("lang", "http://www.w3.org/XML/1998/namespace")&.value }.compact
    end

    # Read up to </teiHeader> (chunked — a long revisionDesc just means
    # another chunk; a file without one yields nothing, honestly).
    def header_slice(path)
      buffer = +""
      File.open(path, "rb") do |io|
        while (chunk = io.read(HEADER_CHUNK))
          buffer << chunk
          if (index = buffer.index(HEADER_END))
            return buffer[0, index + HEADER_END.length].force_encoding(Encoding::UTF_8)
          end
        end
      end
      nil
    end

    # "<en> (<wylie>)" — the en mainTitle with the Wylie parenthesized
    # (the place_index parent-display precedent); either alone when the
    # other is absent; nil when the header names neither.
    def display_title(doc)
      en = main_title(doc, "en")
      wylie = main_title(doc, "Bo-Ltn")&.sub(TRAILING_SLASH, "")
      wylie = nil if wylie.to_s.empty?
      return "#{en} (#{wylie})" if en && wylie

      en || wylie
    end

    def main_title(doc, lang)
      node = doc.xpath("//*[local-name()='title'][@type='mainTitle']" \
                       "[@xml:lang='#{lang}']").first
      return nil if node.nil?

      text = node.text.gsub(/\s+/, " ").strip
      text.empty? ? nil : Normalize.nfc(text)
    end
  end
end
