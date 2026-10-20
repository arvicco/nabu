# frozen_string_literal: true

module Nabu
  module Adapters
    # The translation walk of the Papyri adapter (translations: true): which
    # translation files of the idp.data clone become documents, and which
    # edition each one translates. Parsing is PapyriTranslationParser's.
    #
    # == The two homes (census 2026-10-19, upstream 91611a19)
    #
    # - Translations/<bucket>/<HGV>-<n>.xml — 8,001 files (README's
    #   "HGV_trans_EpiDoc", renamed at the switchover): 7,988 carry text
    #   (en 7,129 · de 576 · fr 190 · it 89 · es/ar/el/pl/bg a handful).
    #   Upstream's own id is the file stem (<HGV>-<n>, papyri.info's
    #   translation key); the -<n> counts several translations of one text
    #   (303 editions carry 2–15 in one language), so the stem — never the
    #   language — is the identity. Upstream authorities: APIS 5,220 (the
    #   APIS translations pulled out of the APIS records in 2026-07,
    #   "Pull translation out of APIS record"), DC3/HGV 2,723, NYU 31,
    #   DCLP 2.
    # - APIS/<collection>/xml/<apisid>.xml — 38,530 catalog records, 5,971
    #   still carrying a translation div. 4,541 of those duplicate a
    #   Translations/ file (same apisid; 4,535 byte-equal text) and yield to
    #   it — upstream's current home; 1,413 exist only here.
    #
    # The APIS records' other divs (figure 12,712, bibliography 39,390) are
    # images and citations, not text. Their descriptive header — the
    # msContents <summary> and the textClass keyword terms — rides each
    # APIS-backed translation verbatim as metadata "description" /
    # "keywords"; the axis-shaped fields (origDate, origPlace) are NOT
    # re-minted: translation documents never row on the timeline (the
    # cross-source "kind" marker), and the edition's axes come from the HGV
    # walk. Deliberate coarseness, declared.
    #
    # == Resolution: which edition a translation belongs to
    #
    # In order, the first hit in the DISCOVERED edition set wins: every
    # ddb-hybrid token (upstream space-separates several — "p.ryl;4;560
    # sb;5;7643"), the dclp idno, every HGV token (the edition files carry
    # their HGV numbers — this reaches re-keyed hybrids such as
    # p.mich;7;443 → chla;5;286, and hybrid-less APIS translations), a TM
    # token that names exactly one edition. A translation whose text is not
    # (yet) in the catalog keeps its own first hybrid (else dclp id) as its
    # edition urn — the translation of an HGV stub is still a text, and it
    # pairs the day the edition lands. Measured on the clone (2026-10-19):
    # 8,225 translation documents (Translations 7,971 · APIS-only 254;
    # eng 7,364 · deu 569 · fra 190 · ita 89 · spa 5 · ara 4 · ell 2 ·
    # pol 1 · bul 1), 7,958 paired with an edition in the catalog, 267
    # under their own hybrid/dclp; 15,826 passages, line-cited in 2,144
    # documents; zero parse failures.
    #
    # == Skipped by rule (censused in #skips, never silent)
    #
    # - files outside upstream's <HGV>-<n>.xml naming (glossary.xml, a
    #   translation glossary; o.krok.1.15-1.xml, a misnamed twin of
    #   88604-1.xml);
    # - empty translation divs (13), unmapped language tags (none today);
    # - APIS translations already carried by Translations/ (4,552);
    # - translations naming no text identity at all (1,174 at the
    #   2026-10-20 census): 15 Translations files (the generic no-edition
    #   reason) and the APIS RECORD-ONLY remainder, 1,159 records — an
    #   apisid/controlNo identity, at most a collection-style ddbdp idno
    #   nothing in the catalog answers to. With no edition to pair and no
    #   stable text namespace to mint under, they are not served: a
    #   standalone APIS document namespace was weighed and declined, so
    #   the remainder is a DECLARED exemption with its own censused reason
    #   (APIS_RECORD_ONLY), never silence and never the generic bucket.
    #
    # == Identity
    #
    # urn = <edition urn>-trans-<stem | apisid>, e.g.
    # urn:nabu:ddbdp:bgu:1:100-trans-8875-1,
    # urn:nabu:dclp:62767-trans-berkeley.apis.253 — the registry's
    # `siblings: ["-trans-…"]` + `sibling_namespaces: [ddbdp, dclp]` serve
    # them to `--parallel` (no edition urn contains "-trans-": hybrids carry
    # no hyphen-word tails, census 2026-10-19).
    class PapyriTranslations
      TRANSLATIONS_ROOT = "Translations"
      APIS_ROOT = "APIS"
      TAIL = "-trans-"
      STEM = /\A\d+[a-z]*-\d+\z/

      NO_EDITION = "names no edition (no hybrid, dclp, HGV or TM the catalog answers to)"
      # The declared exemption (see the class comment): an APIS record whose
      # only identity is its apisid/controlNo — 1,159 records, census
      # 2026-10-20 (upstream 91611a19).
      APIS_RECORD_ONLY = "APIS record-only — apisid/controlNo identity, no edition to pair " \
                         "(exempt: a standalone APIS namespace declined)"

      Skip = Data.define(:name, :reason)

      attr_reader :skips, :refs

      # +bases+: the discovered edition refs (urn:nabu:ddbdp:* and dclp:*).
      def initialize(workdir:, bases:, source_id:)
        @workdir = workdir
        @source_id = source_id
        @skips = []
        index(bases)
        @refs = dedupe(translation_file_refs + apis_refs)
      end

      # The descriptive APIS header of +apisid+ (summary + keyword terms),
      # {} when the record is absent.
      def self.apis_metadata(workdir, apisid)
        return {} if apisid.nil?

        path = File.join(workdir, APIS_ROOT, apisid.split(".").first.to_s, "xml", "#{apisid}.xml")
        return {} unless File.file?(path)

        doc = PapyriTranslationParser.load(path)
        description = PapyriHeader.text(doc.at_xpath("//msContents/summary"))
        keywords = doc.xpath("//textClass/keywords/term").filter_map { |term| PapyriHeader.text(term) }.uniq
        { "description" => description, "keywords" => keywords.empty? ? nil : keywords }.compact
      end

      private

      def index(bases)
        @urns = bases.to_h { |ref| [ref.id, true] }
        @hgv = {}
        @tm = Hash.new { |hash, key| hash[key] = [] }
        bases.sort_by(&:id).each do |ref|
          ref.metadata["hgv"].to_s.split.each { |id| @hgv[id] ||= ref.id }
          ref.metadata["tm"].to_s.split.each { |id| @tm[id] << ref.id }
        end
      end

      def translation_file_refs
        @claimed_apis = {}
        Dir.glob(File.join(@workdir, TRANSLATIONS_ROOT, "**", "*.xml")).filter_map do |path|
          stem = File.basename(path, ".xml")
          next skip(stem, "outside upstream's <HGV>-<n> naming") unless STEM.match?(stem)

          doc = PapyriTranslationParser.load(path)
          apisids(doc).each { |id| @claimed_apis[id] = true }
          ref_for(doc, path, stem)
        end
      end

      def apis_refs
        Dir.glob(File.join(@workdir, APIS_ROOT, "*", "xml", "*.xml")).filter_map do |path|
          next unless File.read(path, encoding: "UTF-8").include?('type="translation"')

          doc = PapyriTranslationParser.load(path)
          apisid = apisids(doc).first || File.basename(path, ".xml")
          next skip(apisid, "APIS translation already carried by Translations/") if @claimed_apis[apisid]

          ref_for(doc, path, apisid, no_edition: APIS_RECORD_ONLY)
        end
      end

      def ref_for(doc, path, id, no_edition: NO_EDITION)
        name = File.basename(path, ".xml")
        return skip(name, "empty translation div") if blank_translation?(doc)
        return skip(name, "unmapped translation language") if PapyriTranslationParser.language_of(doc).nil?

        base = resolve(doc) or return skip(name, no_edition)

        metadata = { "kind" => "translation", "translation_of" => base, "translation_id" => id }
        apisid = apisids(doc).first
        metadata["apisid"] = apisid if apisid
        Nabu::DocumentRef.new(source_id: @source_id, id: "#{base}#{TAIL}#{id}",
                              path: File.expand_path(path), metadata: metadata)
      end

      def resolve(doc)
        hybrids = idnos(doc, "ddb-hybrid").map { |hybrid| "urn:nabu:ddbdp:#{hybrid.tr(';', ':')}" }
        dclps = idnos(doc, "dclp").grep(/\A\d+\z/).map { |id| "urn:nabu:dclp:#{id}" }
        found = (hybrids + dclps).find { |urn| @urns[urn] }
        found ||= idnos(doc, "HGV").filter_map { |id| @hgv[id] }.first
        found ||= idnos(doc, "TM").map { |id| @tm[id] }.find { |urns| urns.size == 1 }&.first
        found || hybrids.first || dclps.first
      end

      def idnos(doc, type)
        doc.xpath("//publicationStmt/idno[@type='#{type}']").flat_map { |node| node.text.split }
      end

      def apisids(doc) = idnos(doc, "apisid")

      def blank_translation?(doc)
        doc.xpath("//body/div[@type='translation']").text.strip.empty?
      end

      # One urn needs one file: a second claimant is censused.
      def dedupe(refs)
        refs.group_by(&:id).map do |_, group|
          kept, *rest = group.sort_by(&:path)
          rest.each { |ref| skip(File.basename(ref.path, ".xml"), "duplicate of #{File.basename(kept.path)}") }
          kept
        end
      end

      def skip(name, reason)
        @skips << Skip.new(name: name, reason: reason)
        nil
      end
    end
  end
end
