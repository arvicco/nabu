# frozen_string_literal: true

module Nabu
  # The annotation-lane test rig: the two declared consumers of
  # Nabu::AnnotationKeys loaded from their REAL fixtures — cantus' chant
  # records (manuscript spellings with Cantus' standardized text in the
  # annotations) and korpus16's Dalmatin Bible page I,56a (marginal notes).
  module TestSupport
    # korpus16 through its own adapter, scoped to the fixture's
    # note-bearing book: book 58 (Dalmatin, Biblia 1584) is held only
    # partially (pages 1 and 200), so the real discovery skips it by rule
    # as a crawl in progress — this subclass discovers it anyway, and the
    # real #parse builds the document from the held pages exactly as it
    # would for a complete crawl.
    class Korpus16BibleOnly < Nabu::Adapters::Korpus16
      BOOK = "58"

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        block.call(Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{BOOK}",
                                         path: File.expand_path(File.join(workdir, "books", BOOK, "00001.html")),
                                         metadata: { "book" => BOOK, "slug" => "biblia" }))
      end

      def discovery_skips(_workdir) = Nabu::DiscoverySkips.new
    end

    def self.korpus16_bible_document
      adapter = Korpus16BibleOnly.new
      adapter.parse(adapter.discover(fixtures("korpus16")).first)
    end

    # Load cantus + korpus16 (the Bible book) into +catalog+; returns
    # {slug => Store::Source}.
    def self.load_annotation_corpus(catalog)
      { "cantus" => [Nabu::Adapters::Cantus, Nabu::Adapters::Cantus.new],
        "korpus16" => [Nabu::Adapters::Korpus16, Korpus16BibleOnly.new] }.to_h do |slug, (klass, adapter)|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: klass.name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: catalog, source: source)
                           .load_from(adapter, workdir: fixtures(slug), full: true)
        [slug, source]
      end
    end
  end
end
