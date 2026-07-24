# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # A pure READ seam over the LiLa Lemma Bank dump (P44-8): given a Latin
  # lemma string (folded per the house Latin fold), return the LiLa canonical
  # lemma record(s) — {lila_id/IRI, canonical form, POS, variant/alternate
  # forms}. There is NO catalog table and NO migration: LiLa is registered as
  # a feature module (kind: module) whose canonical asset is the CIRCSE
  # `rdf/lemmaBank.ttl` Turtle dump, and this resolver reads that dump
  # directly — the Pleiades resolver shape (Nabu::Pleiades), the Latin lemma
  # analogue of the CJK character-desk crosswalks. Its first consumer is the
  # `nabu define` variant-form fallback (Nabu::Query::Define).
  #
  # == The dump shape (grounded in the real bytes, 2026-07-24)
  #
  # `rdf/lemmaBank.ttl` is a D2RQ dump — 215,102 lemmas, 1.7M triples, 84 MB.
  # Every lemma (and hypolemma) is ONE subject block of Turtle, e.g.
  #
  #   lilaLemma:83005  a              lila:Lemma ;
  #           rdfs:label              "subsides" ;
  #           lila:hasPOS             lila:noun ;
  #           dcterms:isPartOf        lilaLemma:LemmaBank ;
  #           ontolex:writtenRep      "subsides"@la .
  #
  # and a variant-carrying one:
  #
  #   lilaIpoLemma:97523  a           lila:Hypolemma ;
  #           rdfs:label              "eclipsans" ;
  #           lila:hasPOS             lila:adjective ;
  #           lila:isHypolemma        lilaLemma:48631 ;
  #           ontolex:writtenRep      "eclypsans"@la , "eclipsans"@la .
  #
  # The four fields this seam reads: the SUBJECT (lilaLemma:<n> → the lila IRI
  # http://lila-erc.eu/data/id/lemma/<n>, lilaIpoLemma:<n> → …/hypolemma/<n>),
  # rdfs:label (the CANONICAL form), lila:hasPOS (the part of speech), and the
  # one-or-more ontolex:writtenRep "<form>"@la values (the canonical PLUS its
  # orthographic VARIANTS — "eclypsans"/"eclipsans", "praeliaris"/"proeliaris",
  # "hamiger"/"amiger"). A Hypolemma is a secondary lemma (participles etc.)
  # carrying its own label/variants and a lila:isHypolemma pointer to its
  # parent Lemma; both are indexed (the variants live on both).
  #
  # == Why a dependency-free line parser, not an RDF gem
  #
  # The dump is machine-emitted D2RQ output: rigidly one triple per line,
  # each subject block terminated by a line ending " .", predicates ending
  # " ;". A full RDF/Turtle parser would be a new gem (forbidden) for no gain
  # over reading the exactly-four line shapes we need — the openiti/pleiades
  # posture (parse what the real bytes carry, justified from them). Line
  # parsing over an 84 MB file is streamed (each_line), and the resolver is
  # loaded LAZILY by its one consumer only on a dictionary miss, so the common
  # `nabu define` path never touches it.
  class Lila
    # One LiLa canonical lemma record. +lila_id+ is the full IRI; +form+ is
    # the rdfs:label (the canonical dictionary form); +pos+ is the bare POS
    # token (noun/verb/adjective/…); +variants+ are every ontolex:writtenRep
    # in file order (the canonical is among them); +hypolemma+ marks a
    # lila:Hypolemma (a secondary lemma) vs a top-level lila:Lemma.
    Record = Data.define(:lila_id, :form, :pos, :variants, :hypolemma) do
      def initialize(hypolemma: false, **) = super
    end

    LEMMA_IRI = "http://lila-erc.eu/data/id/lemma/"
    HYPOLEMMA_IRI = "http://lila-erc.eu/data/id/hypolemma/"
    LILA_LANGUAGE = "lat"

    # The four line shapes the seam reads (class note).
    SUBJECT = /\A(lilaLemma|lilaIpoLemma):(\S+)\s+a\s+lila:(Lemma|Hypolemma)\b/
    LABEL = /\Ardfs:label\s+"([^"]*)"/
    POS = /\Alila:hasPOS\s+lila:(\S+?)\s*[;.]/
    WRITTEN_REP = /"([^"]*)"@la/

    # Build a resolver from a Turtle dump file. Streams the file line by line.
    def self.load(ttl_path)
      File.open(ttl_path, "r:UTF-8") { |io| from_lines(io) }
    end

    # Feature-detect the resolver from the owner's canonical tree (the
    # define fallback's auto-load): nil when `nabu sync lila` has not landed
    # the dump, so a corpus without LiLa behaves byte-identically. The dump
    # lands under canonical/lila/rdf/lemmaBank.ttl (the sparse cone); a
    # flattened canonical/lila/lemmaBank.ttl is accepted too.
    def self.load_default(config: Nabu::Config.load)
      dir = File.join(config.canonical_dir, "lila")
      path = [File.join(dir, "rdf", "lemmaBank.ttl"), File.join(dir, "lemmaBank.ttl")]
             .find { |candidate| File.file?(candidate) }
      path && load(path)
    end

    # Build a resolver from any line-enumerable of the D2RQ Turtle dump (the
    # test/first-sync seam). Indexes every subject block by the folded form of
    # its label AND each written representation, so a query spelled as any
    # variant reaches the record.
    def self.from_lines(lines)
      index = Hash.new { |h, k| h[k] = [] }
      current = nil
      lines.each do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.start_with?("@prefix")

        if (m = SUBJECT.match(stripped))
          current = { prefix: m[1], id: m[2], type: m[3], label: nil, pos: nil, reps: [] }
        elsif current
          collect_predicate(current, stripped)
        end
        # A subject block terminates on a line ending "." (predicates end ";").
        if current && stripped.end_with?(".")
          flush(current, index)
          current = nil
        end
      end
      new(index)
    end

    def self.collect_predicate(current, stripped)
      if (lm = LABEL.match(stripped))
        current[:label] = lm[1]
      elsif (pm = POS.match(stripped))
        current[:pos] = pm[1]
      elsif stripped.start_with?("ontolex:writtenRep")
        current[:reps].concat(stripped.scan(WRITTEN_REP).flatten)
      end
    end
    private_class_method :collect_predicate

    def self.flush(current, index)
      forms = ([current[:label]] + current[:reps]).compact.reject(&:empty?)
      return if forms.empty?

      base = current[:prefix] == "lilaIpoLemma" ? HYPOLEMMA_IRI : LEMMA_IRI
      record = Record.new(
        lila_id: "#{base}#{current[:id]}",
        form: current[:label] || current[:reps].first,
        pos: current[:pos],
        variants: current[:reps].uniq,
        hypolemma: current[:type] == "Hypolemma"
      )
      forms.map { |f| fold(f) }.uniq.each { |key| index[key] << record }
    end
    private_class_method :flush

    # The house Latin fold (Normalize LANGUAGE_FOLDS["lat"]: v→u, j→i, plus
    # NFC + downcase + diacritic strip) — the SAME key the define shelf and
    # query side fold to, so "virtus"/"uirtus" collapse and a LiLa variant
    # lines up with a dictionary headword.
    def self.fold(form)
      Nabu::Normalize.search_form(form, language: LILA_LANGUAGE)
    end

    def initialize(index)
      @index = index
    end

    # Every LiLa record whose canonical form or any written representation
    # folds to +form+ (the Latin fold), deduplicated by lila_id, in a stable
    # order (canonical-form-then-id). [] when the dump holds no such form.
    def lookup(form)
      records = @index[self.class.fold(form.to_s)]
      records.uniq(&:lila_id).sort_by { |r| [r.form.to_s, r.lila_id] }
    end

    # How many distinct folded forms the dump indexed (a diagnostic count, not
    # the lemma count — variants share their record).
    def size
      @index.size
    end
  end
end
