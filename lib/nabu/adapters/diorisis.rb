# frozen_string_literal: true

require "nokogiri"

require_relative "diorisis_parser"

module Nabu
  module Adapters
    # The Diorisis Ancient Greek Corpus (P26-4): Vatri & McGillivray's
    # tokenized, lemmatized and morphologically analyzed corpus of Ancient
    # Greek — 820 XML files / ~10.2M words as ONE frozen figshare v1 zip
    # (2018; 194,443,428 bytes, md5 f3a26efa7e7d2b93d1bcca26900d180a from
    # figshare's own file metadata, sha256-pinned below from the verified
    # download). A thin composition of the DiorisisParser family; the
    # adapter owns identity, the header metadata, the license doctrine, the
    # Rahlfs exclusion and the fetch pin.
    #
    # == THE FIRST SILVER SOURCE (P26-0's tier, occupied at last)
    #
    # Upstream's own in-file words are "corpus conversion and automatic
    # annotation" (every file's editionStmt); the annotation machinery
    # (TreeTagger="true" flags, disambiguated="0.5" 1/n confidence
    # fractions) is visible on the tokens themselves. So sources.yml
    # registers `lemma_tier: silver`: every passage_lemmas row this corpus
    # feeds carries tier "silver", every count renders LABELED (search
    # --lemma "[silver]" tags, ReflexViews silver_count beside a gold-only
    # attested_count, --gold-only exclusion) — automatic lemmatization is
    # never mistakable for verified annotation, and never a bare number.
    #
    # == Second editions, deliberately (the provenance stance)
    #
    # 806 of the 809 works are texts the catalog already holds (742 Perseus,
    # 102 First1K — scout text-diffed samples). Diorisis documents mint as
    # their OWN source's documents: provenance-distinct SECOND EDITIONS (the
    # MW-beside-kaikki precedent), because the value is the lemma layer —
    # silver counts at scale over a canon whose Perseus/First1K editions
    # carry no annotations at all. No dedup, no cross-linking; the honest
    # two-witness shape.
    #
    # == License (the in-file doctrine's third proof)
    #
    # figshare's page claims CC BY 4.0; EVERY ONE of the 820 files' own
    # publicationStmt declares CC BY-SA 3.0 US. The in-file license GOVERNS
    # (the doctrine's third proof, after ASPR and SARIT): the manifest quotes
    # both, class `attribution` either way.
    #
    # == THE RAHLFS EXCLUSION (02-sources row 44)
    #
    # 53 of the 820 files are the Septuagint — tlgAuthor 0527, sourceDesc
    # "Bibliotheca Augustana" (the harsch/graeca Rahlfs-lineage LXX; the
    # scout text-diffed them divergent from our held Swete tlg0527). Rahlfs'
    # machine-readable lineage is CATSS-encumbered (row 44: permission
    # DECLINED by the rights holder), so these files are EXCLUDED by the
    # machine-readable per-file header field: discover skips tlgAuthor 0527
    # by rule (censused in discovery_skips — 53 upstream, honest and quiet)
    # and parse refuses it belt-and-braces. The FETCH keeps the zip's tree
    # whole (canonical preserves the artifact; the exclusion is a discovery
    # rule, never a fetch mutilation).
    #
    # == fetch / update channel
    #
    # ZipFetch of the figshare artifact with a hard sha256 pin (the IE-CoR
    # choreography: prepare → verify pin → breaker → complete; a mismatch
    # aborts with the tree untouched — figshare v1 is immutable, so a
    # mismatch is corruption or tampering, never an update). Upstream ALSO
    # runs a token-gated JSON update channel (per-file v1.6 versions vs this
    # 2018 XML zip) — a future-refresh watch item journaled in sources.yml;
    # the figshare zip stays the pinned artifact. sync_policy manual,
    # enabled: false until the owner-fired first sync.
    class Diorisis < Nabu::Adapter
      # The figshare v1 artifact (article 6187256, DOI
      # 10.6084/m9.figshare.6187256.v1).
      ZIP_URL = "https://ndownloader.figshare.com/files/11296247"

      # sha256 of the 194,443,428-byte zip, pinned from the 2026-07-18
      # census download whose md5 (f3a26efa7e7d2b93d1bcca26900d180a) matched
      # figshare's published computed_md5 exactly. A mismatch aborts before
      # any tree mutation.
      ZIP_SHA256 = "fb32b7ff4bcfc433f1234aff8134096f524c9a32accbfdf0a072df4a5f019b65"

      # The excluded Septuagint author id (row 44; class note).
      LXX_TLG_AUTHOR = "0527"

      LANGUAGE = "grc"

      URN_PREFIX = "urn:nabu:diorisis:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "diorisis",
        name: "Diorisis Ancient Greek Corpus (Vatri & McGillivray, figshare v1 2018)",
        license: "CC BY-SA 3.0 US (in-file, all 820 files: \"Creative Commons " \
                 "Attribution-ShareAlike 3.0 United States License\" — the in-file declaration " \
                 "governs over the figshare page's \"CC BY 4.0\" claim; cite Vatri & " \
                 "McGillivray 2018, doi:10.6084/m9.figshare.6187256.v1)",
        license_class: "attribution",
        upstream_url: "https://figshare.com/articles/dataset/The_Diorisis_Ancient_Greek_Corpus/6187256",
        parser_family: "diorisis"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD the figshare artifact: reachability + Last-Modified drift
      # against the .zip-fetch.json pin. metadata_url nil — the governing
      # license lives inside the artifact's files (in-file doctrine), and
      # the figshare API body carries volatile stats that would false-alarm
      # a hash comparison.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Diorisis.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the zip sha (tests; a deliberate owner re-pin drill).
      def initialize(pin: ZIP_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per corpus XML file whose header peek passes the
      # Rahlfs exclusion, sorted by urn. The header (tlgAuthor/tlgId +
      # metadata) is read ONCE here — streamed, never a whole-file DOM (76
      # files exceed 5 MB) — and rides the ref to parse. A pre-fetch workdir
      # yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The discovery census (P11-7): the LXX files discover skips by rule —
      # an explicit, benign, rights-driven skip (53 upstream; class note).
      def discovery_skips(workdir)
        skipped = corpus_files(workdir).count { |path| lxx?(header(path)) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      # The belt-and-braces refusal, then the parser family over the body.
      def parse(document_ref)
        header = document_ref.metadata
        if header["tlg_author"] == LXX_TLG_AUTHOR
          raise ParseError,
                "#{document_ref.path}: tlgAuthor 0527 is the Septuagint — Rahlfs-lineage, " \
                "CATSS-encumbered (02-sources row 44); excluded by rule, never ingested"
        end

        DiorisisParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE,
          title: document_title(header),
          metadata: document_metadata(header)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (the IE-CoR choreography);
      # a 304 replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "diorisis fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "diorisis: downloaded artifact misses the sha256 pin (expected #{@pin}, " \
              "got #{fetch.sha}) — the figshare v1 zip is immutable, so this is corruption " \
              "or tampering; verify #{ZIP_URL} against the figshare record before re-pinning"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "figshare v1 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end

      # The urn is <prefix><tlgAuthor>:<tlgId>, but upstream REUSES a tlgId
      # across genuinely distinct works: the whole-corpus census (2026-07-22,
      # P39-4) found two collision groups — Diodorus Siculus 0060:001 split
      # into three book-range volumes (Books I-V / XI-XVII / XVIII-XX) and
      # Aristotle 0086:029 shipped twice (Economics / Oeconomica II). All five
      # are distinct texts (distinct titles, sizes, bodies), not duplicates, so
      # a bare tlgAuthor:tlgId is NOT unique and the last file parsed silently
      # overwrote its siblings (glob-order-dependent; owner rebuild saw
      # `~3 updated` on a from-scratch load — the same urn minted three times).
      # Fix: a base shared by more than one file is disambiguated by a slug of
      # its work title. SINGLETONS keep the bare base urn BYTE-IDENTICAL — only
      # a colliding group shifts — so the 815 non-colliding works never re-mint.
      # A residual same-title collision (none in the frozen v1 corpus) is left
      # for the loader's collision seam (P39-4) to flag loudly, never resolved
      # by a filesystem artifact.
      def document_refs(workdir)
        entries = corpus_files(workdir).filter_map do |path|
          header = header(path)
          next if lxx?(header)

          [File.expand_path(path), header]
        end
        disambiguate(entries).sort_by(&:id)
      end

      def disambiguate(entries)
        entries.group_by { |_path, header| base_urn(header) }.flat_map do |base, group|
          group.map do |path, header|
            id = group.size == 1 ? base : "#{base}:#{title_slug(header)}"
            Nabu::DocumentRef.new(source_id: manifest.id, id: id, path: path, metadata: header)
          end
        end
      end

      def base_urn(header)
        "#{URN_PREFIX}#{header.fetch('tlg_author')}:#{header.fetch('tlg_id')}"
      end

      def title_slug(header)
        header["title"].to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      # The zip unpacks flat: 820 XML files at the workdir root (the fixture
      # README is not corpus shape and never matches).
      def corpus_files(workdir)
        Dir.glob(File.join(workdir, "*.xml"))
      end

      def lxx?(header)
        header["tlg_author"] == LXX_TLG_AUTHOR
      end

      def document_title(header)
        [header["author"], header["title"]].compact.reject(&:empty?).join(" — ")
      end

      # Everything discover peeked, minus the raw title/author pair that
      # became the document title.
      def document_metadata(header)
        header.except("title", "author")
              .merge("author" => header["author"], "work" => header["title"]).compact
      end

      # The teiHeader subtree, streamed: Nokogiri::XML::Reader walks the file
      # only as far as the header's end (a few KB into even the 76 MB files),
      # and the small subtree fragment is then read as a document of its own.
      # Missing/malformed headers raise ParseError at discover — a corpus
      # file without its identity block is damage, not a rule.
      def header(path)
        fragment = header_fragment(path)
        raise ParseError, "#{path}: no <teiHeader> found" if fragment.nil?

        parse_header(fragment, path)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML header: #{e.message}"
      end

      def header_fragment(path)
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            return node.outer_xml if node.name == "teiHeader" &&
                                     node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          end
        end
        nil
      end

      def parse_header(fragment, path)
        doc = Nokogiri::XML(fragment)
        tlg_author = doc.at_xpath("//titleStmt/tlgAuthor")&.text
        tlg_id = doc.at_xpath("//titleStmt/tlgId")&.text
        if tlg_author.nil? || tlg_author.empty? || tlg_id.nil? || tlg_id.empty?
          raise ParseError, "#{path}: teiHeader carries no tlgAuthor/tlgId identity"
        end

        provenance = doc.at_xpath("//fileDesc/sourceDesc/ref")
        {
          "tlg_author" => tlg_author, "tlg_id" => tlg_id,
          "title" => doc.at_xpath("//titleStmt/title")&.text,
          "author" => doc.at_xpath("//titleStmt/author")&.text,
          "genre" => doc.at_xpath("//xenoData/genre")&.text,
          "subgenre" => doc.at_xpath("//xenoData/subgenre")&.text,
          "creation_date" => doc.at_xpath("//profileDesc/creation/date")&.text,
          "provenance" => provenance&.text,
          "provenance_url" => provenance&.attribute("target")&.value
        }.compact
      end
    end
  end
end
