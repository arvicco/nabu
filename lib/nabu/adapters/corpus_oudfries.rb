# frozen_string_literal: true

require_relative "../manual_drop"
require_relative "../shell"
require_relative "oudfries_tei_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # Corpus Oudfries: the Old Frisian (ofs) corpus of the INT/IvdNT, v1.0
    # (2026, hdl 10032/tm-a3-f6), compiled and annotated by Rita van de Poel
    # (Leiden PhD). Old Frisian text witnesses c. 1200–1550 (mostly the
    # customary laws), lemmatised and PoS-tagged. Parser family oudfries-tei.
    #
    # == License / acquisition: the corpus-oudnederlands posture
    #
    # INT non-commercial, no redistribution grant → research_private (the
    # strictest reading): local research ingest only, never redistributed,
    # default-excluded from MCP, and NO corpus bytes in the public repo. The
    # archive carries no licence member of its own (README.txt is a corpus
    # description + citation string only); the terms are the INT
    # Taalmaterialen download terms the sibling corpora were accepted under.
    # Behind the taalmaterialen login → the Manual Adapter pattern (ruling
    # Dp-a): the owner drops upstream's own CorpusOudfries1.0.zip into
    # incoming/corpus-oudfries/; the ZIP is the canonical asset. See
    # docs/manual/corpus-oudfries.md.
    #
    # == Reading the zip
    #
    # Members are listed and read through `unzip` (Nabu::Shell — the
    # coptic-scriptorium zip-member precedent) and validated through the
    # SourceRead belt; nothing is unpacked, so rebuild stays a pure function
    # of canonical/. Member names are plain ASCII sigla (censused: no unzip
    # wildcard characters); a name carrying one is refused, never globbed.
    #
    # == Delivery grains and the reconciliation (censused 2026-10-27)
    #
    # 180 entries: 2 directories; 1 README.txt (documentation — skipped by
    # rule, counted in discovery_skips); 177 Data/*.xml text witnesses
    # (document = witness; urn = the filename stem before the first dot,
    # E1-Hav.tei.3.exported.xml → E1-Hav). 177 = upstream's README ("177
    # text witnesses from 11 manuscripts (114 distinct texts)") = the public
    # BlackLab index's 177 documents; the witnesses' 235,462 <w> tokens = the
    # index's 235,462 tokens exactly. Passages = <l> lines: 14,154 lines, 18
    # with no <w> skipped by rule → 14,136 passages.
    #
    # == The mined axes
    #
    # Dating: the WITNESS span (manuscript_year_from/_to, every file) rides
    # not_before/not_after — the timeline's artifact date. The attributed
    # COMPOSITION span (text_year_from/_to, 76 of 177) rides its own
    # composition_* keys: metadata-carried, deliberately not a second
    # timeline row (one axis row per document; the witness date is the
    # attestation claim). Places: manuscript_region (6 Frisian lands,
    # every file) at REGION grain — declared coarse, no town. Dialect
    # (East/West Old Frisian), manuscript, region and the genre ladder
    # (text_category_1..3) facet via config/facet_map.yml; genre folds
    # through config/kind_map.yml.
    class CorpusOudfries < Nabu::Adapter
      SLUG = "corpus-oudfries"
      ZIP_NAME = "CorpusOudfries1.0.zip"
      LANGUAGE = "ofs"
      WITNESS_MEMBER = %r{(?:\A|/)Data/[^/]+\.xml\z}
      README_MEMBER = %r{(?:\A|/)README\.txt\z}i
      UNZIP_WILDCARD = /[*?\[\]\\]/
      YEAR = /\A\d{3,4}\z/
      private_constant :WITNESS_MEMBER, :README_MEMBER, :UNZIP_WILDCARD, :YEAR

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Corpus Oudfries — Old Frisian text witnesses c. 1200–1550, lemma+POS (INT/IvdNT)",
        license: "INT non-commercial (\"Niet-commercieel\"); no redistribution grant → " \
                 "strictest reading: local research ingest only, never redistributed",
        license_class: "research_private",
        upstream_url: "https://taalmaterialen.ivdnt.org/download/corpus-oudfries-download/",
        parser_family: "oudfries-tei"
      )

      def self.manifest = MANIFEST

      # Account-gated, dropped by hand: no unattended upstream to probe.
      def self.upstream_repo_urls = []

      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: SLUG,
          upstream_url: MANIFEST.upstream_url,
          steps: [
            "Register once at https://taalmaterialen.ivdnt.org/registreren/ and log in " \
            "(a personal identity act — never an automated agent)",
            "Open the Corpus Oudfries download page and CAPTURE THE LICENSE TEXT " \
            "verbatim (screenshot/copy) at the checkbox BEFORE agreeing",
            "Download the corpus archive (#{ZIP_NAME}) and keep its name",
            "Drop it as listed below"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: ZIP_NAME,
              description: "the Corpus Oudfries TEI archive (research_private — never redistributed)",
              required: true, sniff: ->(path) { zip_complaint(path) }
            )
          ],
          refresh_hint: "INT deposits are versioned (hdl 10032/tm-a3-f6, v1.0) — a new version " \
                        "ships a new filename: re-pin ZIP_NAME and re-acquire; re-acceptance of " \
                        "terms may be required."
        )
      end

      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", SLUG), workdir)
      end

      # A readable ZIP carrying at least one Data/*.xml witness; a saved
      # login page or a truncated download is not. One sentence.
      def self.zip_complaint(path)
        return nil if zip_members(path).any? { |name| name.match?(WITNESS_MEMBER) }

        "no Data/*.xml witness members — is this the Corpus Oudfries download?"
      rescue Nabu::Shell::Error
        "not a readable ZIP archive (a saved login/registration page?)"
      end

      def self.zip_members(path)
        Nabu::Shell.run("unzip", "-Z1", path).split("\n").reject { |name| name.end_with?("/") }
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition, drop_dir: self.class.drop_dir(workdir),
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end

      # One ref per Data/*.xml witness, sorted stably. No dropped archive →
      # nothing (the pre-acquisition state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        zip = zip_path(workdir) or return
        members(zip).grep(WITNESS_MEMBER).sort.each do |member|
          block.call(Nabu::DocumentRef.new(
                       source_id: SLUG, id: "urn:nabu:#{SLUG}:#{stem(member)}",
                       path: File.expand_path(zip), metadata: { "member" => member }
                     ))
        end
      end

      # README.txt is the one documentation member (skipped by rule); any
      # other non-witness file would be unrecognized — loud.
      def discovery_skips(workdir)
        zip = zip_path(workdir) or return super
        others = members(zip).grep_v(WITNESS_MEMBER)
        readme, strays = others.partition { |name| name.match?(README_MEMBER) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: readme.size, unrecognized: strays.size,
          notes: readme.map { |name| "documentation member (corpus description): #{name}" } +
                 strays.map { |name| "unrecognized member: #{name}" }
        )
      end

      def parse(document_ref)
        member = document_ref.metadata.fetch("member")
        xml = SourceRead.utf8(member_bytes(document_ref.path, member), label: "#{document_ref.path}!#{member}")
        text = OudfriesTeiParser.new.text(xml, name: member)
        build_document(document_ref, text)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      end

      private

      def build_document(document_ref, text)
        meta = text.meta
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(meta, document_ref), metadata: document_metadata(document_ref, meta)
        )
        text.lines.each do |line|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{line.seq}", language: LANGUAGE,
            text: line.text, sequence: line.seq - 1,
            annotations: { "tokens" => line.tokens, "n" => line.n }.compact
          )
        end
        raise ParseError, "#{document_ref.id}: no lines carrying words" if document.empty?

        document
      end

      def title_for(meta, document_ref)
        [meta["title_text_EN"], stem(document_ref.metadata.fetch("member"))].compact.join(" — ")
      end

      # Upstream's interp types → house keys (the witness span on the
      # timeline keys, the composition span beside it).
      HEADER_KEYS = {
        "title" => "sigil", "text_abbreviation" => "text_abbreviation",
        "title_text_EN" => "title_en", "title_text_NL" => "title_nl",
        "Gerbenzon_number" => "gerbenzon_number", "edition" => "edition", "remarks" => "remarks",
        "manuscript_code" => "manuscript_code", "manuscript_title_EN" => "manuscript",
        "manuscript_title_NL" => "manuscript_nl", "manuscript_region" => "region",
        "manuscript_dialect_EN" => "dialect", "manuscript_dialect_NL" => "dialect_nl"
      }.freeze
      GENRE_KEYS = %w[text_category_1 text_category_2 text_category_3].freeze
      private_constant :HEADER_KEYS, :GENRE_KEYS

      def document_metadata(document_ref, meta)
        out = HEADER_KEYS.to_h { |upstream, key| [key, meta[upstream]] }
        out["genre"] = meta.values_at(*GENRE_KEYS).compact.uniq
        out.merge!(span(meta, "manuscript_year", prefix: ""))
        out.merge!(span(meta, "text_year", prefix: "composition_"))
        out["member"] = document_ref.metadata.fetch("member")
        out.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      # {<prefix>not_before, <prefix>not_after, <prefix>date_raw} from the
      # <field>_from/_to pair; a non-year value mints no bound (raw keeps it).
      def span(meta, field, prefix:)
        from = meta["#{field}_from"]
        to = meta["#{field}_to"]
        return {} if from.nil? && to.nil?

        { "#{prefix}not_before" => year(from), "#{prefix}not_after" => year(to),
          "#{prefix}date_raw" => [from, to].compact.join("-") }
      end

      def year(value)
        value.to_s.match?(YEAR) ? Integer(value, 10) : nil
      end

      # The filename stem before the first dot (E3-Aug.tei.3.rita.exported.xml → E3-Aug).
      def stem(member)
        File.basename(member)[/\A[^.]+/]
      end

      def zip_path(workdir)
        direct = File.join(workdir, ZIP_NAME)
        return direct if File.file?(direct)

        Dir.glob(File.join(workdir, "*.zip")).min
      end

      # One member listing per archive path, shared across discover and the
      # discovery census (the loader reuses one adapter instance).
      def members(zip)
        (@members ||= {})[zip] ||= self.class.zip_members(zip)
      rescue Nabu::Shell::Error => e
        raise FetchError, "#{zip}: unreadable zip archive (unzip exit #{e.status}) — re-drop the download"
      end

      def member_bytes(zip, member)
        raise ParseError, "#{member}: member name carries an unzip wildcard — refused" if member.match?(UNZIP_WILDCARD)

        Nabu::Shell.run("unzip", "-p", zip, member)
      rescue Nabu::Shell::Error => e
        raise ParseError, "#{zip}!#{member}: unreadable zip member (unzip exit #{e.status})"
      end
    end
  end
end
