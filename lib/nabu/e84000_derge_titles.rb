# frozen_string_literal: true

require "nokogiri"
require_relative "adapters/e84000"

module Nabu
  # The 84000 → Derge title crosswalk (P106-5 — the Q78 e84000 lode 2):
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
    HEADER_END = "</teiHeader>"
    HEADER_CHUNK = 1 << 16
    # Wylie titles close with the shad rendered "/" — a display title
    # drops it (key_raw-style verbatim keeping is the glossary lane's
    # business; this is our own minted display field).
    TRAILING_SLASH = %r{[\s/]+\z}

    Result = Data.define(:titled, :missing_docs, :files)

    def initialize(catalog:, canonical_dir:)
      @catalog = catalog
      @canonical_dir = canonical_dir
    end

    def run
      titles = crosswalk_titles
      return Result.new(titled: 0, missing_docs: 0, files: 0) if titles.empty?

      titled = 0
      missing = 0
      @catalog.transaction do
        titles.each do |(prefix, key), title|
          updated = @catalog[:documents].where(urn: "#{prefix}#{key}").update(title: title)
          updated.positive? ? titled += updated : missing += 1
        end
      end
      Result.new(titled: titled, missing_docs: missing, files: @files)
    end

    private

    # {[shelf urn prefix, toh key] => display title} over every 84000
    # header. Placeholders first, then published (hash overwrite = the
    # published-wins rule); files sorted for determinism within each tier.
    def crosswalk_titles
      @files = 0
      workdir = File.join(@canonical_dir, E84000_SLUG)
      return {} unless Dir.exist?(workdir)

      titles = {}
      placeholder_files(workdir).each { |path, prefix| harvest(path, prefix, titles) }
      published_files(workdir).each { |path, prefix| harvest(path, prefix, titles) }
      titles
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

    def harvest(path, prefix, titles)
      header = header_slice(path) or return
      doc = Nokogiri::XML(header, &:recover)
      title = display_title(doc) or return

      @files += 1
      doc.xpath("//*[local-name()='bibl'][@type='text']/@key").each do |key|
        value = key.value.to_s.strip
        titles[[prefix, value]] = title unless value.empty?
      end
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
