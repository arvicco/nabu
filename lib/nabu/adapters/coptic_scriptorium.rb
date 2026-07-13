# frozen_string_literal: true

module Nabu
  module Adapters
    # The Coptic Scriptorium adapter (P17-1, docs/coptic-survey.md): ONE git
    # source for github.com/CopticScriptorium/corpora — 77 corpora / ~2,390
    # documents / ~2.38M words of literary Sahidic and Bohairic Coptic with
    # gold-to-automatic lemma/POS/deprel, entities + Wikification,
    # language-of-origin loanword tags, per-verse English translation and
    # manuscript metadata. The machine-readable source of record is the
    # TreeTagger-SGML `*.tt` layer (upstream's own "most complete
    # representations" — see CopticTtParser); TEI is absent for the two
    # biggest corpora and CoNLL-U is deferred (v2 FEATS join).
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:coptic-scriptorium:<cts-tail>, the upstream-minted
    # document_cts_urn minus its urn:cts:copticLit:/copticDoc: namespace
    # (besa.food.monbbb, nt.mark.sahidica, papyri_info.tm82127.cpr_2_237).
    # Bible CHAPTER files (meta `chapter` + a ":<n>" urn suffix) merge into
    # per-book documents — the CTS work id is shared by a book's chapters,
    # so the merge is a grouping, not surgery; a single-chapter book
    # (Philemon) merges the same way. Passage urns append the citation
    # (chapter.verse for scripture, the vid_n tail for literary texts,
    # ordinals flagged non-canonical for the documentary corpora); duplicate
    # citations take the ":b2" collision suffix (the ccmh/GRETIL precedent).
    #
    # == License (survey §3 — the P10-4 pattern, inverted proportion)
    #
    # Source class `nc` = most-restrictive-present: the Sahidica NT's
    # J. Warren Wells "academic use only" terms (witness #14 — the PROIEL-NT
    # posture: local research fine, MCP-withheld, never redistributed) and
    # a CC BY-NC-SA quartet. ~87% of documents are CC-BY(-SA) and carry
    # `license_override: attribution`, read from each document's own
    # `license` header field — never hardcoded (the ORACC precedent).
    # book.bartholomew's three license-less documents are skipped by rule
    # and counted in the discovery accounting. Unknown terms classify nc —
    # carried under the restrictive posture, never dropped.
    #
    # == fetch / sync policy: pinned release tag
    #
    # Upstream is a living master with semiannual tagged releases (survey
    # §2). Registry sync_policy is `manual`, and the fetch itself is PINNED
    # to RELEASE_TAG (GitFetch ref:) — never master, which moves between
    # releases; the owner re-pins by bumping the constant per release (the
    # "versioned" verdict). Clone ~2.8 GB one-time; ~1 GB of that is
    # ANNIS/PAULA dead weight this adapter never reads (honest cost).
    #
    # == Discovery
    #
    # Walks <corpus>/<corpus>_TT/*.tt plus the four big bible corpora's
    # in-repo <corpus>_TT.zip archives (their loose CoNLL-U files are 2-byte
    # placeholders upstream; zip members are listed and read via the system
    # unzip through Nabu::Shell — canonical/ is never written outside
    # #fetch). Each file's one-line meta header is peeked for the cts urn,
    # chapter and license. The `coptic-treebank`/`bohairic-treebank` dirs
    # are upstream-documented duplicate collections — excluded by rule,
    # counted. Known cost: a full-corpus discover spawns one unzip per zip
    # member (~2k) to read headers; acceptable at sync cadence, noted here.
    #
    # The UD-source dedup guard runs the other way: UD_Coptic-Scriptorium
    # must never enter the `ud` TREEBANKS map while this source is live
    # (the chu-PROIEL exclusion, inverted — the native repo is richer).
    class CopticScriptorium < Nabu::Adapter
      REPO_URL = "https://github.com/CopticScriptorium/corpora"

      # The pinned release ("Late 2025 Release", 2025-12-12; Zenodo DOI
      # 10.5281/zenodo.17917497). Owner re-pins per semiannual release.
      RELEASE_TAG = "v6.2.0"

      URN_PREFIX = "urn:nabu:coptic-scriptorium:"
      CTS_NAMESPACE = /\Aurn:cts:coptic(?:Lit|Doc):/
      CHAPTER_SUFFIX = /:\d+\z/

      # Upstream-documented duplicate collections (README: "identical to the
      # same documents in the source corpora") — excluded by rule.
      EXCLUDED_DIRS = %w[coptic-treebank bohairic-treebank].freeze

      LANGUAGE = "cop"

      # Roster/meta fields unioned across a book's chapter files.
      ROSTER_KEYS = %w[people places].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "coptic-scriptorium",
        name: "Coptic Scriptorium corpora (release #{RELEASE_TAG})",
        license: "per-document (header `license` field): CC BY 3.0/4.0 or CC BY-SA for ~87% of documents " \
                 "(attribution overrides); Sahidica NT \"(c)2000-2006 by J Warren Wells, for academic use " \
                 "only\" + CC BY-NC-SA quartet -> source class nc (most restrictive present, P10-4); " \
                 "3 license-less docs skipped by rule",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "coptic-tt"
      )

      def self.manifest
        MANIFEST
      end

      # Survey §3 verbatim license classes → license_class. nil = no stated
      # terms (the skip rule); nc patterns FIRST (BY-NC contains "BY").
      # Unknown terms are nc: carried restrictively, never guessed open.
      def self.license_class_of(license)
        return nil if license.nil? || license.strip.empty?

        return "nc" if license.match?(/academic use only|BY-NC/i)
        return "attribution" if license.match?(%r{CC[- ]?BY|creativecommons\.org/licenses/by|public domain}i)

        "nc"
      end

      # The gold-lemma gate (survey §4b): :gold mints index lemmas from
      # gold/checked documents only; :all is the owner's "include automatic"
      # flip (a re-parse away, no schema change).
      def initialize(lemmas: :gold)
        super()
        @lemmas = lemmas
      end

      # One DocumentRef per document, chapter files merged per book, sorted
      # by urn. Returns an Enumerator without a block; an unfetched workdir
      # yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        scan(workdir).refs.each(&block)
      end

      # The P11-7 census: treebank-duplicate and license-less files are
      # skipped_by_rule (benign, counted); a TT file or zip member whose
      # header yields no cts urn is unrecognized (a defect, named).
      def discovery_skips(workdir)
        result = scan(workdir)
        DiscoverySkips.new(skipped_by_rule: result.skipped_by_rule,
                           unrecognized: result.unrecognized.size,
                           notes: result.unrecognized.map { |label| "no usable TT meta header: #{label}" })
      end

      # Assemble the document from its chunks (files or zip members) in
      # chapter order: diplomatic text, norm-derived search form minted
      # through the ONE folding boundary, unit annotations as parsed.
      def parse(document_ref)
        chunks = document_ref.metadata.fetch("chunks")
        parser = CopticTtParser.new(lemmas: @lemmas)
        results = chunks.map { |chunk| parser.parse(chunk_content(chunk), label: chunk_label(chunk)) }
        document = build_document(document_ref, results)
        citations = Hash.new(0)
        results.each do |result|
          result.units.each { |unit| append(document, document_ref, unit, citations) }
        end
        raise ParseError, "#{document_ref.path}: no passages parsed" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Clone-or-pull PINNED to the release tag via the shared
      # non-destructive git path (attic + mass-deletion breaker). A re-pin
      # (owner bumps RELEASE_TAG) fast-forwards; master is never tracked.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, ref: RELEASE_TAG)
      end

      # The internal walk result (constant scoped here, not private —
      # Data.define constants ignore access modifiers anyway).
      Scan = Data.define(:refs, :skipped_by_rule, :unrecognized)

      private

      # Overridable for tests (the PROIEL/SBLGNT local-repo pattern).
      def repo_url
        REPO_URL
      end

      # One walk shared by discover and discovery_skips: peek every eligible
      # TT header, apply the skip rules, group chapters into books.
      def scan(workdir)
        skipped = 0
        unrecognized = []
        chunks = []
        loose_tt_files(workdir).each do |path|
          if excluded?(workdir, path)
            skipped += 1
            next
          end
          meta = CopticTtParser.header(path)
          outcome = classify(meta, chunks, source: { "path" => path }, label: path)
          skipped += 1 if outcome == :skipped
          unrecognized << path if outcome == :unrecognized
        end
        zip_files(workdir).each do |zip|
          each_zip_member(zip) do |member, content|
            meta = CopticTtParser.meta(content.each_line.first.to_s)
            label = "#{zip}!#{member}"
            outcome = classify(meta, chunks, source: { "zip" => zip, "member" => member }, label: label)
            skipped += 1 if outcome == :skipped
            unrecognized << label if outcome == :unrecognized
          end
        end
        refs, shadowed = build_refs(chunks)
        Scan.new(refs: refs, skipped_by_rule: skipped + shadowed, unrecognized: unrecognized)
      end

      # :chunk (usable), :skipped (license-less — the book.bartholomew
      # rule), :unrecognized (no meta/cts urn — a defect, named upstream).
      def classify(meta, chunks, source:, label:)
        return :unrecognized if meta.nil? || meta["document_cts_urn"].nil?

        klass = self.class.license_class_of(meta["license"])
        return :skipped if klass.nil?

        chunks << source.merge("meta" => meta, "license_class" => klass, "label" => label)
        :chunk
      end

      def loose_tt_files(workdir)
        Dir.glob(File.join(workdir, "**", "*_TT", "*.tt"))
      end

      def zip_files(workdir)
        Dir.glob(File.join(workdir, "**", "*_TT.zip")).reject { |zip| excluded?(workdir, zip) }
      end

      def excluded?(_workdir, path)
        EXCLUDED_DIRS.any? { |dir| path.split(File::SEPARATOR).include?(dir) }
      end

      # Discover-time zip walking. A zip that cannot be listed or read HERE
      # is a snapshot problem, not a document problem — FetchError (aborts
      # the sync; refetch is the remedy), the counterpart of chunk_content's
      # parse-time quarantine.
      def each_zip_member(zip)
        members = Shell.run("unzip", "-Z1", zip).split("\n").grep(/\.tt\z/).sort
        members.each { |member| yield member, Shell.run("unzip", "-p", zip, member) }
      rescue Shell::Error => e
        raise FetchError, "#{zip}: unreadable zip archive at discover (unzip exit #{e.status}) — refetch the snapshot"
      end

      # Group chunks by base work urn (the chapter→book merge), apply the
      # dual-origin precedence rule, order chapters numerically, and mint one
      # ref per document. The override is attribution only when EVERY chunk
      # of the document is open-class. Returns [refs, shadowed-chunk count].
      def build_refs(chunks)
        shadowed = 0
        refs = chunks.group_by { |chunk| document_urn(chunk["meta"]) }.map do |urn, group|
          group, dropped = prefer_standalone(group)
          shadowed += dropped
          group = group.sort_by { |chunk| chunk["meta"]["chapter"].to_i }
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: urn, path: ref_path(group.first),
            metadata: {
              "language" => LANGUAGE,
              "title" => document_title(group),
              "license_override" => (group.all? { |c| c["license_class"] == "attribution" } ? "attribution" : nil),
              "chunks" => group.map { |chunk| chunk.slice("path", "zip", "member") }
            }.compact
          )
        end.sort_by(&:id)
        [refs, shadowed]
      end

      # The dual-origin precedence rule (P17-10, "zip member shadowed by the
      # standalone edition"). Upstream mints distinct `_ed` CTS urns for its
      # standalone digital editions (nt.mark.sahidica_ed loose vs
      # nt.mark.sahidica zip) — EXCEPT Habakkuk, where the bohairic.ot zip
      # members reuse ot.hab.bohairic_ed. The census over v6.2.0 found the
      # two origins byte-different: the standalone corpus is the NEWER
      # release of the same edition (v6.2.0, segmentation/tagging/parsing/
      # entities all gold, people/places rosters, lb_n manuscript topology)
      # while the zip member is the frozen v6.0.0 automatic snapshot. So the
      # standalone (loose) chunks win deterministically; the shadowed zip
      # members are counted skipped_by_rule — never doubled chapters in one
      # document, never an unzip against a loose .tt file.
      def prefer_standalone(group)
        loose, zipped = group.partition { |chunk| chunk["path"] }
        return [group, 0] if loose.empty? || zipped.empty?

        [loose, zipped.size]
      end

      # urn:nabu:coptic-scriptorium:<cts-tail>, the chapter suffix stripped
      # for chapter files (shared work id). FROZEN once used.
      def document_urn(meta)
        tail = meta["document_cts_urn"].sub(CTS_NAMESPACE, "")
        tail = tail.sub(CHAPTER_SUFFIX, "") if meta["chapter"]
        "#{URN_PREFIX}#{tail}"
      end

      def ref_path(chunk)
        File.expand_path(chunk["zip"] || chunk["path"])
      end

      # Literary documents keep the upstream title; a merged book drops the
      # per-chapter "_<n>" tail ("41_Mark_1" → "41_Mark").
      def document_title(group)
        title = group.first["meta"]["title"]
        return title unless group.first["meta"]["chapter"]

        title&.sub(/_\d+\z/, "")
      end

      # Every chunk is read from its OWN origin (P17-10): the zip path comes
      # from the chunk itself, NEVER from document_ref.path — ref path is the
      # first chunk's file, and a mixed-origin group must be structurally
      # incapable of unzipping a loose .tt (the owner's exit-9 crash). An
      # unreadable/corrupt zip MEMBER at parse time quarantines the document
      # (ParseError — backlog 5a), it never aborts the sync; a zip that fails
      # at discover is a FetchError (see each_zip_member).
      def chunk_content(chunk)
        return File.read(chunk.fetch("path")) unless chunk["zip"]

        zip = File.expand_path(chunk.fetch("zip"))
        member = chunk.fetch("member")
        begin
          Shell.run("unzip", "-p", zip, member)
        rescue Shell::Error => e
          raise ParseError, "#{zip}!#{member}: unreadable zip member (unzip exit #{e.status})"
        end
      end

      def chunk_label(chunk)
        chunk["zip"] ? "#{chunk['zip']}!#{chunk['member']}" : chunk["path"]
      end

      # Document metadata = the first chunk's full decoded header (maximum
      # fidelity, JSON-safe) with "dialect" surfaced, the chapter fields
      # dropped for merged books, and the people/places rosters UNIONED
      # across chapters (the §3.5 prosopography seed at document grain).
      def build_document(document_ref, results)
        meta = results.first.meta.dup
        if meta["chapter"]
          meta.delete("chapter")
          meta["document_cts_urn"] = meta["document_cts_urn"].sub(CHAPTER_SUFFIX, "")
          ROSTER_KEYS.each do |key|
            union = results.flat_map { |r| (r.meta[key] || "").split(/;\s*/) }.uniq - ["none", ""]
            meta[key] = union.join("; ") unless union.empty?
          end
        end
        # literary headers say language=, the NT chapter headers languages=
        dialect = meta["language"] || meta["languages"]
        meta["dialect"] = dialect if dialect
        Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata["title"],
          canonical_path: document_ref.path, metadata: meta,
          license_override: document_ref.metadata["license_override"]
        )
      end

      def append(document, document_ref, unit, citations)
        citations[unit.citation] += 1
        count = citations[unit.citation]
        citation = count == 1 ? unit.citation : "#{unit.citation}:b#{count}"
        text = Normalize.nfc(unit.text)
        document << Nabu::Passage.new(
          urn: "#{document_ref.id}:#{citation}", language: LANGUAGE, text: text,
          text_normalized: Normalize.search_form(
            CopticTtParser.search_source(text, unit.annotations), language: LANGUAGE
          ),
          annotations: unit.annotations, sequence: document.size
        )
      end
    end
  end
end
