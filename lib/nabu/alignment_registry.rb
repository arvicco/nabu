# frozen_string_literal: true

require "yaml"

require_relative "errors"
require_relative "model/validation"

module Nabu
  # The alignment-hub registry (P11-3, architecture §10, config/alignments.yml):
  # the declarative side of cross-source alignment. A WORK groups the witnesses
  # that carry the same text under a shared citation scheme (the flagship `nt`
  # work: five PROIEL-family New Testament witnesses); a WITNESS is one catalog
  # document named by urn, plus how its citation refs are extracted and, when
  # its book tokens differ from the work's vocabulary, mapped.
  #
  # Adding a witness is a registry entry, never code — the whole point. What IS
  # code is the closed extractor set (EXTRACTORS): a new citation shape (e.g.
  # CTS verse suffixes for the P11-5 biblical trio) lands as one new named
  # extractor in Store::AlignmentIndexer plus registry entries using it.
  #
  # Like SourceRegistry, the file is parsed and validated up front and every
  # malformed shape raises ValidationError naming the offending work/witness —
  # a silently mis-parsed registry would mean a silently empty alignment index.
  class AlignmentRegistry
    # Citation extractors the indexer implements (architecture §10). v1:
    # proiel-citation — the distinct per-token citation_part values of a
    # PROIEL/TOROT sentence's stored annotations.
    EXTRACTORS = %w[proiel-citation].freeze
    DEFAULT_EXTRACTOR = "proiel-citation"

    # One witness: the catalog document, its extractor, its display label
    # (defaults to the urn tail: urn:nabu:proiel:greek-nt → "greek-nt"), and
    # its book-alias map (witness book token → work vocabulary, applied AFTER
    # the generic ref fold).
    Witness = Data.define(:document_urn, :extractor, :label, :books) do
      # The witness-local normal form of +ref+: the generic fold, then the
      # witness's book aliases. Index side and query side both come through
      # here — the fold-both-sides contract (conventions §9, architecture §10).
      def normalize_ref(ref)
        folded = AlignmentRegistry.normalize_ref(ref)
        return folded if folded.nil? || books.empty?

        book, rest = folded.split(" ", 2)
        replacement = books[book]
        replacement && rest ? "#{replacement} #{rest}" : folded
      end
    end

    # One work: id, display title (defaults to the id), witnesses in registry
    # order — which IS the display order of the aligned rendering.
    Work = Data.define(:id, :title, :witnesses) do
      def witness_for(document_urn)
        witnesses.find { |witness| witness.document_urn == document_urn }
      end
    end

    # The generic ref fold: whitespace collapsed, uppercased, `:` → `.` — so a
    # query spelled "Mark 2:3" meets rows indexed "MARK 2.3". Refs are opaque
    # strings scoped to their work; non-verse refs (Gothic "MARK Incipit.0")
    # fold like any other and stay addressable. nil for blank input.
    def self.normalize_ref(ref)
      folded = ref.to_s.strip.split(/\s+/).join(" ").upcase.tr(":", ".")
      folded.empty? ? nil : folded
    end

    # Parse config/alignments.yml at +path+. A missing or empty file is a
    # valid, empty registry (alignment is an opt-in layer). Any structural or
    # per-entry problem raises ValidationError naming the offender.
    def self.load(path)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      unless data.is_a?(Hash)
        raise ValidationError, "alignment registry must be a mapping of work id => entry, got #{data.class}"
      end

      new(data.map { |id, config| build_work(id, config) })
    end

    def self.build_work(id, config)
      unless id.is_a?(String) && id.match?(Model::Validation::SLUG_SHAPE)
        raise ValidationError, "alignment work #{id.inspect}: id must be a lowercase slug ([a-z0-9_-])"
      end
      unless config.is_a?(Hash)
        raise ValidationError, "alignment work #{id.inspect}: entry must be a mapping, got #{config.class}"
      end

      witnesses = config["witnesses"]
      unless witnesses.is_a?(Array) && !witnesses.empty?
        raise ValidationError, "alignment work #{id.inspect}: witnesses must be a non-empty list"
      end

      built = witnesses.map { |witness| build_witness(id, witness) }
      duplicate = built.map(&:document_urn).tally.find { |_, count| count > 1 }
      raise ValidationError, "alignment work #{id.inspect}: duplicate witness document #{duplicate[0]}" if duplicate

      Work.new(id: id, title: string_or(config["title"], default: id), witnesses: built)
    end
    private_class_method :build_work

    def self.build_witness(work_id, config)
      unless config.is_a?(Hash)
        raise ValidationError, "alignment work #{work_id.inspect}: each witness must be a mapping, got #{config.class}"
      end

      document = config["document"]
      unless document.is_a?(String) && document.start_with?("urn:")
        raise ValidationError,
              "alignment work #{work_id.inspect}: witness document must be a document urn, got #{document.inspect}"
      end

      Witness.new(
        document_urn: document,
        extractor: extractor!(work_id, document, config),
        label: string_or(config["label"], default: document.split(":").last),
        books: books!(work_id, document, config)
      )
    end
    private_class_method :build_witness

    def self.extractor!(work_id, document, config)
      extractor = config.fetch("extractor", DEFAULT_EXTRACTOR)
      return extractor if EXTRACTORS.include?(extractor)

      raise ValidationError,
            "alignment work #{work_id.inspect}, witness #{document}: unknown extractor " \
            "#{extractor.inspect} (known: #{EXTRACTORS.join(', ')})"
    end
    private_class_method :extractor!

    def self.books!(work_id, document, config)
      books = config.fetch("books", {})
      valid = books.is_a?(Hash) &&
              books.all? { |from, to| from.is_a?(String) && to.is_a?(String) }
      unless valid
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{document}: books must be a " \
              "mapping of witness book token => work book token"
      end

      books.to_h { |from, to| [normalize_ref(from), normalize_ref(to)] }.freeze
    end
    private_class_method :books!

    def self.string_or(value, default:)
      value.is_a?(String) && !value.strip.empty? ? value : default
    end
    private_class_method :string_or

    attr_reader :works

    def initialize(works)
      @works = works.freeze
    end

    def work(id)
      @works.find { |work| work.id == id }
    end

    # The single registered work, when exactly one exists — what lets
    # `nabu align` omit --work in the common one-work registry.
    def sole_work
      @works.size == 1 ? @works.first : nil
    end

    def empty?
      @works.empty?
    end
  end
end
