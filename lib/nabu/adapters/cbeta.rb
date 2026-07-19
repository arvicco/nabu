# frozen_string_literal: true

require_relative "cbeta_tei_parser"

module Nabu
  module Adapters
    # The CBETA adapter (P33-2; sino-survey lanes SINO-D/E): the Chinese
    # Buddhist Electronic Text Archive's TEI P5 corpus from
    # github.com/cbeta-org/xml-p5, scoped THIS PHASE to the two central
    # canons — T (Taishō Tripiṭaka 大正新脩大藏經, vols 1–85) and X
    # (Xuzangjing 卍新纂大日本續藏經, vols 1–88).
    #
    # == Repo census (master 2b8ab8d "CBETA 2026.R1", 2026-05-10; ~1.2 GB)
    #
    # canons.json declares 29 canons; 26 ship as top-level dirs (Q/R/Z are
    # apparatus-witness editions with no dir). Layout
    # <canon>/<canon><vol>/<canon><vol>n<work>.xml, pure XML:
    # T = 2,471 files / 815.9 MB (27 files > 5 MB, max 17.2 MB T25n1509);
    # X = 1,236 files / 645.1 MB (7 > 5 MB, max 9.0 MB X04n0223);
    # schema/ = cbeta-p5.rnc + .rng (508 KB); canons.json 6 KB.
    #
    # == THE CANON-LEVEL LICENSE GATE (cbeta.org/copyright, read 2026-07-20)
    #
    # CBETA's 版權宣告 splits the corpus at CANON grain (the Sefaria
    # precedent). Category A ("類別 A：隨本站以創用 CC 條款共同開放之文獻" —
    # T, X and the other listed canons) is released, verbatim: 「除下方
    # 「二、底本來源與授權分類」中特別註明不適用之文獻外，本資料庫未特別說明處皆
    # 採用「Creative Commons 姓名標示-非商業性-相同方式分享 4.0 國際授權條款」
    # 釋出。」 (CC BY-NC-SA 4.0), corroborated per file by the availability
    # header (CbetaTeiParser::AVAILABILITY_GRANT, re-verified at every
    # parse) → license_class "nc": local research use, MCP-excluded by
    # class, never redistributed.
    #
    # Category B ("類別 B：不屬於創用 CC 條款授權之文獻" — distribution
    # rights only, NOT CC) is NEVER ingested. The named list, verbatim from
    # the copyright page, IS the CATEGORY_B constant below; #discover
    # refuses LOUDLY (FetchError) if any of those canon dirs ever appears in
    # the workdir, and the fetch cone never asks for them. Other Category A
    # canons beyond T/X (J, K, N, …) are out of THIS phase's scope: skipped
    # by rule, censused in discovery_skips, a future scope decision.
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:cbeta:<filename stem> — upstream's own stable id
    # (T85n2884 = canon T, vol 85, work No. 2884; the stem regex is the
    # gate). Passage urns append the print-line citation (see the parser).
    # The one trimmed fixture carries a suffixed stem (T01n0001-xu), so
    # fixture urns never collide with corpus urns (the SARIT rule).
    #
    # == fetch (GitFetch sparse cone)
    #
    # The flat top-level canon layout takes a sparse cone cleanly:
    # SPARSE_CONE = T/ + X/ + canons.json + schema/ ≈ 1.43 GiB working tree
    # (818 MB + 645 MB + 0.5 MB) instead of the full 26-canon checkout —
    # and the cone is ALSO the Category B firewall: excluded dirs are never
    # materialized. Shared non-destructive path (attic + mass-deletion
    # breaker). Upstream ships dated releases (2026.R1) → sync_policy
    # manual; a fresh cone lands the current release.
    #
    # == Overlap honesty (SuttaCentral lzh, measured 2026-07-20 — nothing
    #    promised)
    #
    # SuttaCentral's 272 root/lzh/sct documents are RE-EDITED Taishō texts
    # ("SuttaCentral Taisho", CC0) — provenance-distinct witnesses of the
    # same works, NEVER deduped against this source. Measured against the
    # synced suttacentral canonical tree: all 272 map onto SEVEN Taishō
    # numbers, every one present in T — 207 docs carry the number in their
    # own uid (t765.* ×140 → T17n0765, t1536.* ×33 → T26n1536, t1537.* ×22
    # → T26n1537, t1548.* ×12 → T28n1548) and 65 map via SuttaCentral's own
    # documented Āgama correspondences (ma ×15 → T01n0026, sa ×49 →
    # T02n0099, ea19 ×1 → T02n0125). Reference edges are a future producer
    # decision, not minted here.
    class Cbeta < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "cbeta",
        name: "CBETA — Chinese Buddhist Electronic Text Archive (Taishō + Xuzangjing, TEI P5)",
        license: "CC BY-NC-SA 4.0 — cbeta.org/copyright Category A verbatim: 「Creative Commons " \
                 "姓名標示-非商業性-相同方式分享 4.0 國際授權條款」; per-file header: \"Available for " \
                 "non-commercial use when distributed with this header intact.\"",
        license_class: "nc",
        upstream_url: "https://github.com/cbeta-org/xml-p5",
        parser_family: "cbeta-tei"
      )

      # This phase's ingest scope: the two central canons (owner-widened).
      CANONS = %w[T X].freeze

      # Category B, verbatim from cbeta.org/copyright (類別 B：不屬於創用 CC
      # 條款授權之文獻 — read 2026-07-20): canon dir code → named corpus.
      # NEVER ingested; #discover refuses on sight, the fetch cone never
      # asks. Test-pinned.
      CATEGORY_B = {
        "Y" => "印順法師佛學著作集（印順文教基金會 ©）",
        "LC" => "呂澂佛學著作集（呂應中等 ©）",
        "TX" => "太虛大師全書（印順文教基金會 ©）",
        "YP" => "演培法師全集（演培法師全集出版委員會 ©）"
      }.freeze

      # The sparse checkout cone (P26-0 GitFetch mechanics): scope canons +
      # the canon registry + the RelaxNG schema. ≈1.43 GiB of working tree
      # at 2026.R1; everything else — including every Category B dir —
      # is never materialized.
      SPARSE_CONE = ["T/", "X/", "canons.json", "schema/"].freeze

      # Upstream's own filename grammar: <canon><vol>n<work>.xml
      # (T85n2884, X01n0001, T85n2917A). The stem IS the document id.
      STEM = /\A(?<canon>[A-Z]{1,2})(?<vol>\d{2,3})n(?<work>.+)\z/

      def self.manifest
        MANIFEST
      end

      # Walk the scope canon dirs (<workdir>/T/T01/*.xml …), one ref per
      # file, sorted by urn — after refusing any Category B canon dir
      # LOUDLY. Pure filename walk: no file is opened (breaker-friendly);
      # titles are captured at parse.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        refuse_category_b!(workdir)
        document_refs(workdir).each(&block)
      end

      # Non-scope Category A canon dirs (J, K, N, … — a future scope
      # decision) are skipped by rule; an xml under T/X whose stem defies
      # upstream's own grammar is unrecognized, loudly (P11-7).
      def discovery_skips(workdir)
        skipped = out_of_scope_files(workdir).size
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped, unrecognized: strays.size,
          notes: strays.map { |path| "unrecognized filename stem: #{path}" }
        )
      end

      def parse(document_ref)
        CbetaTeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          canon: document_ref.metadata["canon"]
        )
      end

      # Clone or non-destructively pull the sparse cone (attic +
      # mass-deletion breaker). No network in tests: exercised against a
      # local fixture repo.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_CONE)
      end

      private

      # Split out so fetch tests can point a singleton at a local git
      # tmpdir (the house pattern).
      def repo_url
        manifest.upstream_url
      end

      # The canon-dir refusal — the Category B gate's last line of defense
      # behind the sparse cone. Loud (aborts the sync), never silent.
      def refuse_category_b!(workdir)
        present = CATEGORY_B.keys.select { |code| Dir.exist?(File.join(workdir, code)) }
        return if present.empty?

        names = present.map { |code| "#{code} = #{CATEGORY_B[code]}" }.join(", ")
        raise FetchError, "#{manifest.id}: Category B canon dir(s) present in #{workdir}: #{names} — " \
                          "cbeta.org/copyright 類別 B is not CC-licensed and is never ingested"
      end

      def document_refs(workdir)
        scope_files(workdir).filter_map do |path|
          stem = File.basename(path, ".xml")
          match = STEM.match(stem)
          next unless match

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:cbeta:#{stem}",
            path: File.expand_path(path),
            metadata: { "canon" => match[:canon], "vol" => match[:vol], "work" => match[:work] }
          )
        end.sort_by(&:id)
      end

      def scope_files(workdir)
        CANONS.flat_map { |canon| Dir.glob(File.join(workdir, canon, "*", "*.xml")) }
      end

      def stray_files(workdir)
        scope_files(workdir).reject { |path| STEM.match?(File.basename(path, ".xml")) }
      end

      # xml files under top-level canon dirs outside the scope. Category B
      # dirs are excluded here too: their presence is a refusal (#discover
      # raises), never a benign skip census line.
      def out_of_scope_files(workdir)
        out_of_scope = Dir.children(workdir).select do |entry|
          Dir.exist?(File.join(workdir, entry)) && !CANONS.include?(entry) &&
            !CATEGORY_B.key?(entry) && entry != Nabu::Adapter::ATTIC_DIRNAME && entry != "schema"
        end
        out_of_scope.flat_map { |entry| Dir.glob(File.join(workdir, entry, "**", "*.xml")) }
      end
    end
  end
end
