# frozen_string_literal: true

require "yaml"

require_relative "errors"
require_relative "model/validation"

module Nabu
  # The alignment-hub registry (P11-3, architecture §10, config/alignments.yml):
  # the declarative side of cross-source alignment. A WORK groups the witnesses
  # that carry the same text under a shared citation scheme (the flagship `nt`
  # work: five PROIEL-family New Testament witnesses); a WITNESS is one
  # EDITION — either one catalog document named by urn (`document:`), or, since
  # P11-5, a SET of per-book documents (`documents:`, a map of work-vocabulary
  # book token => document urn — the shape of the LXX's Swete book-documents
  # and the Vulgate's per-book minting) — plus how its citation refs are
  # extracted and, when its book tokens differ from the work's vocabulary,
  # mapped.
  #
  # Adding a witness is a registry entry, never code — the whole point. What IS
  # code is the closed extractor set (EXTRACTORS): a new citation shape lands
  # as one new named extractor in Store::AlignmentIndexer plus registry entries
  # using it. The two shipped extractors pair with the two witness forms:
  # proiel-citation reads per-token citation_part values (single `document:`),
  # cts-verse reads the passage-urn tail prefixed with the document's registry
  # book token (`documents:` map).
  #
  # Like SourceRegistry, the file is parsed and validated up front and every
  # malformed shape raises ValidationError naming the offending work/witness —
  # a silently mis-parsed registry would mean a silently empty alignment index.
  class AlignmentRegistry
    # Citation extractors the indexer implements (architecture §10).
    # proiel-citation (P11-3): the distinct per-token citation_part values of
    # a PROIEL/TOROT sentence's stored annotations. cts-verse (P11-5): the
    # registry book token + the passage urn's citation tail ("1.2" →
    # "GEN 1.2") — verse-grain CTS-style editions.
    EXTRACTORS = %w[proiel-citation cts-verse].freeze
    DEFAULT_EXTRACTOR = "proiel-citation"

    # A per-witness VERSIFICATION remap (P13-5, architecture §10): the witness
    # numbers its psalms/chapters in a DIFFERENT system than the work
    # vocabulary. The psalms work speaks the Greek/LXX numbering the
    # Septuagint and Vulgate share; the WEB English psalter is Hebrew/
    # Masoretic-numbered (Greek Psalm 22 = Hebrew 23, and so on). +system+ is
    # the provenance label surfaced on the aligned row; +ranges+ is the
    # piecewise-linear map on the LEADING citation segment (the psalm number):
    # each rule shifts a [from, to] span of witness numbers by +shift+ into
    # the work vocabulary. A number NO rule covers is DROPPED — the ref is not
    # indexed at all, so the psalms the LXX joins/splits (Hebrew 9, 10, 114,
    # 115, 116, 147) attest per-witness only rather than false-align onto a
    # Greek psalm they do not equal (the fold-both-sides honesty of §10).
    Numbering = Data.define(:system, :ranges) do
      # The work-vocabulary number for witness number +num+, or nil to drop.
      def remap(num)
        rule = ranges.find { |range| num.between?(range.from, range.to) }
        rule && (num + rule.shift)
      end
    end

    # One rule of a Numbering map: witness numbers [from, to] shift into the
    # work vocabulary by +shift+ (0 = the systems already agree in this span).
    NumberingRange = Data.define(:from, :to, :shift)

    # One witness. +documents+ is an ordered frozen map of document urn =>
    # book token — the token is nil for the single-`document:` form (whose
    # refs carry their own book) and a work-vocabulary token for the
    # `documents:` form. +label+ is the display label (defaults to the urn
    # tail for the single form; required for the documents form). +books+
    # maps witness book tokens into the work vocabulary, applied AFTER the
    # generic ref fold. +numbering+ (P13-5) is an optional versification remap
    # applied AFTER the book alias, on the leading psalm/chapter number.
    Witness = Data.define(:documents, :extractor, :label, :books, :numbering) do
      def document_urns
        documents.keys
      end

      # The representative urn — the single form's document, a multi-document
      # witness's first book (reporting surfaces only; queries walk
      # document_urns).
      def document_urn
        documents.each_key.first
      end

      def book_for(urn)
        documents[urn]
      end

      # The witness-local normal form of +ref+: the generic fold, then the
      # witness's book aliases, then its versification remap. Index side and
      # query side both come through here — the fold-both-sides contract
      # (conventions §9, architecture §10). Returns nil when the numbering map
      # DROPS the ref (a psalm the witness's system cannot map one-to-one onto
      # the work vocabulary), so the indexer's compact/filter_map skip it.
      def normalize_ref(ref)
        folded = AlignmentRegistry.normalize_ref(ref)
        return folded if folded.nil?

        aliased = apply_book_alias(folded)
        numbering ? apply_numbering(aliased) : aliased
      end

      def apply_book_alias(folded)
        return folded if books.empty?

        book, rest = folded.split(" ", 2)
        replacement = books[book]
        replacement && rest ? "#{replacement} #{rest}" : folded
      end

      # Remap the leading psalm/chapter number of a folded "BOOK cite" ref
      # through the witness's Numbering. A non-numeric or verse-less leading
      # segment passes through untouched; a number no rule covers drops the
      # whole ref (nil).
      def apply_numbering(folded)
        book, cite = folded.split(" ", 2)
        return folded if cite.nil?

        chapter, dot, rest = cite.partition(".")
        return folded unless chapter.match?(/\A\d+\z/)

        mapped = numbering.remap(chapter.to_i)
        mapped.nil? ? nil : "#{book} #{mapped}#{dot}#{rest}"
      end
    end

    # One work: id, display title (defaults to the id), witnesses in registry
    # order — which IS the display order of the aligned rendering.
    Work = Data.define(:id, :title, :witnesses) do
      def witness_for(document_urn)
        witnesses.find { |witness| witness.document_urns.include?(document_urn) }
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
      duplicate = built.flat_map(&:document_urns).tally.find { |_, count| count > 1 }
      raise ValidationError, "alignment work #{id.inspect}: duplicate witness document #{duplicate[0]}" if duplicate

      Work.new(id: id, title: string_or(config["title"], default: id), witnesses: built)
    end
    private_class_method :build_work

    def self.build_witness(work_id, config)
      unless config.is_a?(Hash)
        raise ValidationError, "alignment work #{work_id.inspect}: each witness must be a mapping, got #{config.class}"
      end
      if config.key?("document") && config.key?("documents")
        raise ValidationError,
              "alignment work #{work_id.inspect}: a witness declares document: OR documents:, not both"
      end

      config.key?("documents") ? build_multi_witness(work_id, config) : build_single_witness(work_id, config)
    end
    private_class_method :build_witness

    # The single-`document:` form (P11-3): one catalog document whose stored
    # refs carry their own book tokens (proiel-citation).
    def self.build_single_witness(work_id, config)
      document = config["document"]
      unless document.is_a?(String) && document.start_with?("urn:")
        raise ValidationError,
              "alignment work #{work_id.inspect}: witness document must be a document urn, got #{document.inspect}"
      end

      extractor = extractor!(work_id, document, config)
      if extractor == "cts-verse"
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{document}: the cts-verse extractor needs " \
              "a documents: book-token map (its refs are built from book token + passage-urn tail)"
      end

      Witness.new(
        documents: { document => nil }.freeze,
        extractor: extractor,
        label: string_or(config["label"], default: document.split(":").last),
        books: books!(work_id, document, config),
        numbering: numbering!(work_id, document, config)
      )
    end
    private_class_method :build_single_witness

    # The `documents:` form (P11-5): one edition spanning per-book documents,
    # keyed by work-vocabulary book token (cts-verse).
    def self.build_multi_witness(work_id, config)
      label = config["label"]
      unless label.is_a?(String) && !label.strip.empty?
        raise ValidationError,
              "alignment work #{work_id.inspect}: a documents: witness needs an explicit label"
      end

      extractor = extractor!(work_id, label, config)
      unless extractor == "cts-verse"
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{label}: extractor #{extractor.inspect} takes a " \
              "single document: — only cts-verse reads a documents: book map"
      end

      Witness.new(
        documents: documents!(work_id, label, config["documents"]),
        extractor: extractor,
        label: label,
        books: books!(work_id, label, config),
        numbering: numbering!(work_id, label, config)
      )
    end
    private_class_method :build_multi_witness

    # The book-token => urn map, inverted into ordered {urn => TOKEN} with
    # tokens folded through the generic normal form (so `gen:` and `GEN:` key
    # the same refs).
    def self.documents!(work_id, label, mapping)
      shape_ok = mapping.is_a?(Hash) && !mapping.empty? &&
                 mapping.all? { |book, urn| book.is_a?(String) && !book.strip.empty? && urn.is_a?(String) }
      unless shape_ok
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{label}: documents must be a non-empty " \
              "mapping of book token => document urn"
      end

      inverted = mapping.to_h do |book, urn|
        unless urn.start_with?("urn:")
          raise ValidationError,
                "alignment work #{work_id.inspect}, witness #{label}: #{book.inspect} must map to a " \
                "document urn, got #{urn.inspect}"
        end
        [urn, normalize_ref(book)]
      end
      if inverted.size < mapping.size
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{label}: duplicate document urn in documents:"
      end

      inverted.freeze
    end
    private_class_method :documents!

    def self.extractor!(work_id, witness_name, config)
      extractor = config.fetch("extractor", DEFAULT_EXTRACTOR)
      return extractor if EXTRACTORS.include?(extractor)

      raise ValidationError,
            "alignment work #{work_id.inspect}, witness #{witness_name}: unknown extractor " \
            "#{extractor.inspect} (known: #{EXTRACTORS.join(', ')})"
    end
    private_class_method :extractor!

    def self.books!(work_id, witness_name, config)
      books = config.fetch("books", {})
      valid = books.is_a?(Hash) &&
              books.all? { |from, to| from.is_a?(String) && to.is_a?(String) }
      unless valid
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{witness_name}: books must be a " \
              "mapping of witness book token => work book token"
      end

      books.to_h { |from, to| [normalize_ref(from), normalize_ref(to)] }.freeze
    end
    private_class_method :books!

    # The optional per-witness versification remap (P13-5): a system: label and
    # a non-empty ranges: list of {from, to, shift} integer rules. nil when the
    # witness declares no numbering: (the common case — its numbering already
    # is the work vocabulary).
    def self.numbering!(work_id, witness_name, config)
      return nil unless config.key?("numbering")

      spec = config["numbering"]
      unless spec.is_a?(Hash) && string_or(spec["system"], default: nil) && spec["ranges"].is_a?(Array) &&
             !spec["ranges"].empty?
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{witness_name}: numbering must be a mapping " \
              "with a non-empty system: label and a non-empty ranges: list"
      end

      ranges = spec["ranges"].map { |rule| numbering_range!(work_id, witness_name, rule) }
      Numbering.new(system: spec["system"], ranges: ranges.freeze)
    end
    private_class_method :numbering!

    def self.numbering_range!(work_id, witness_name, rule)
      valid = rule.is_a?(Hash) && [rule["from"], rule["to"], rule["shift"]].all?(Integer) &&
              rule["from"] <= rule["to"]
      unless valid
        raise ValidationError,
              "alignment work #{work_id.inspect}, witness #{witness_name}: each numbering range needs " \
              "integer from:/to:/shift: with from <= to, got #{rule.inspect}"
      end

      NumberingRange.new(from: rule["from"], to: rule["to"], shift: rule["shift"])
    end
    private_class_method :numbering_range!

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
