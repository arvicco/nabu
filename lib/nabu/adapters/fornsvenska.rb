# frozen_string_literal: true

require_relative "sparv_parser"

module Nabu
  module Adapters
    # The Fornsvenska textbanken adapter (P77-6): Old Swedish laws,
    # prose and verse from Språkbanken Text (University of Gothenburg) —
    # the P77 phase's Germanic rung: Äldre Västgötalagen and the
    # medieval law codes, the religious and profane prose, and the
    # rhymed chronicles/Eufemiavisorna, over the NEW sparv family.
    #
    # == Scope (P77-6 v1)
    #
    # The SEVEN fornsvenska parts only. The five fsv-nysvensk* siblings
    # are EARLY MODERN Swedish (1526+) — a different language stage that
    # must not ride an Old Swedish claim; they join later with their own
    # posture if wanted.
    #
    # == Identity (FROZEN minting)
    #
    # Document = one <text> of a part (the works upstream marks: one law,
    # one chronicle), urn = urn:nabu:fornsvenska:<title slugified> (the
    # ren/rundata ASCII slugify; a duplicate slug across the discover set
    # takes the -b2 positional belt). Passage = one SENTENCE, cited
    # <paragraph>.<sentence-in-paragraph> — upstream's own grain (the
    # files are "meningsmängder", sentence sets); the opaque sentence
    # @id rides the "sentence_id" annotation verbatim. Minting frozen
    # once used.
    #
    # == Language and dating
    #
    # `sv` for every document — Old Swedish has NO ISO 639-3 code (the
    # IcePaHC-under-`is` precedent); the sv:old stage rule is №R-32
    # (register), the lect posture pending on it. Each text carries
    # upstream's own dating attrs (date/datefrom/dateto — "1280–1290",
    # YYYYMMDD bounds) verbatim in document metadata: the dating
    # posture's named candidate.
    #
    # == License
    #
    # CC-BY-4.0, stated per part on the Språkbanken resource pages, each
    # with a DOI (fsv-aldrelagar: doi.org/10.23695/6bcv-5386).
    #
    # == Fetch
    #
    # Seven per-part FileFetch targets (the ccmh mold: one subdir each —
    # FileFetch keeps one state file per dir), two-phase so the
    # mass-deletion breaker sees the union before any tree mutation.
    # Upstream frozen since 2013-10-08 → sync_policy manual. The .bz2
    # bytes ARE the canonical asset; parse decompresses through
    # Nabu::Shell (bzcat) and SAX-parses the stream (a part decompresses
    # to tens of MB — never a DOM).
    class Fornsvenska < Nabu::Adapter
      BASE_URL = "https://spraakbanken.gu.se/resurser/meningsmangder"

      PARTS = %w[fsv-aldrelagar fsv-yngrelagar fsv-aldrereligiosprosa
                 fsv-yngrereligiosprosa fsv-profanprosa fsv-verser
                 fsv-yngretankebocker].freeze

      LANGUAGE = "sv"

      URN_PREFIX = "urn:nabu:fornsvenska:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "fornsvenska",
        name: "Fornsvenska textbanken — Old Swedish laws, prose and verse (Språkbanken Text)",
        license: "CC-BY-4.0 (stated per part on the Språkbanken resource pages, each with a " \
                 "DOI — fsv-aldrelagar: doi.org/10.23695/6bcv-5386)",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "sparv"
      )

      def self.manifest
        MANIFEST
      end

      # One DocumentRef per <text>, parts in PARTS order, texts in file
      # order. A workdir without the files (pre-fetch) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        slugs = Hash.new(0)
        PARTS.each do |part|
          path = find_part(workdir, part) or next
          texts(path).each_with_index do |text, index|
            slug = self.class.slug_for(text.title)
            slugs[slug] += 1
            slug = "#{slug}-b#{slugs[slug]}" unless slugs[slug] == 1
            yield Nabu::DocumentRef.new(
              source_id: manifest.id, id: "#{URN_PREFIX}#{slug}", path: path,
              metadata: { "part" => part, "index" => index, "title" => text.title }
            )
          end
        end
      end

      def parse(document_ref)
        text = texts(document_ref.path).fetch(document_ref.metadata.fetch("index"))
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: text.title,
          canonical_path: document_ref.path, metadata: metadata(document_ref, text)
        )
        text.sentences.each_with_index do |sentence, sequence|
          annotations = {}
          annotations["sentence_id"] = sentence.id if sentence.id
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{sentence.citation}", language: LANGUAGE,
            text: Normalize.nfc(sentence.text), annotations: annotations, sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path}: #{text.title.inspect} parsed to zero sentences" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download the seven part files via FileFetch, two-phase (the ccmh
      # choreography): prepare all, run the breaker once over the union,
      # then complete.
      def fetch(workdir, progress: nil, force: false)
        fetches = part_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        report(fetches)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "fornsvenska fetch failed into #{workdir}: #{e.message}"
      end

      # The ren/rundata ASCII slugify.
      def self.slug_for(title)
        ascii = title.unicode_normalize(:nfkd)
                     .encode(Encoding::US_ASCII, invalid: :replace, undef: :replace, replace: "")
        slug = ascii.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        raise ParseError, "title #{title.inspect} slugifies to nothing" if slug.empty?

        slug
      end

      private

      # One part's parsed texts — single-slot memo: refs arrive grouped
      # by part in discover order, so the previous part's tree is freed
      # as the next one loads (a part decompresses to tens of MB).
      def texts(path)
        return @texts if @texts_path == path

        @texts_path = path
        @texts = SparvParser.new.parse(Nabu::Shell.run("bzcat", path))
      end

      def metadata(document_ref, text)
        meta = { "part" => document_ref.metadata.fetch("part") }
        meta["date"] = text.date if text.date
        meta["datefrom"] = text.datefrom if text.datefrom
        meta["dateto"] = text.dateto if text.dateto
        meta
      end

      def find_part(workdir, part)
        Dir.glob(File.join(workdir, "**", "#{part}.xml.bz2")).min
      end

      def part_fetches(workdir, progress)
        PARTS.to_h do |part|
          [part, Nabu::FileFetch.new(
            url: "#{BASE_URL}/#{part}.xml.bz2", dir: File.join(workdir, part),
            filename: "#{part}.xml.bz2",
            attic_dir: File.join(workdir, ATTIC_DIRNAME, part), progress: progress
          )]
        end
      end

      def report(fetches)
        shas = fetches.transform_values(&:sha)
        Nabu::FetchReport.new(
          sha: shas.values.last, fetched_at: Time.now,
          notes: attic_notes(fetches.values.flat_map(&:atticked)),
          repos: shas.transform_keys { |part| "#{BASE_URL}/#{part}.xml.bz2" }
        )
      end
    end
  end
end
