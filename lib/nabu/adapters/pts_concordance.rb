# frozen_string_literal: true

module Nabu
  module Adapters
    # The PTS / VRI concordance carried by SuttaCentral's reference sidecars
    # (bilara-data reference/<lang>/<edition>/…/<stem>_reference.json): each
    # segment's comma-separated edition-reference string names, among a
    # dozen print editions, the Pali Text Society page it starts on
    # ("pts-vp-pli4.16") and the VRI Chaṭṭha Saṅgāyana reference
    # ("vri26.15"). This module folds those tokens into passage-grain
    # concordance keys; BilaraJsonParser carries them as the "pts" / "vri"
    # annotations beside the verbatim "refs" string.
    #
    # == The key notation is CBETA's (the house PTS precedent)
    #
    # The library already carries PTS page anchors: CBETA's N canon (the
    # Japanese Nanden Daizōkyō) records <ref cRef="PTS.S.3.1"/> per line as
    # its "cref" annotation — PTS siglum, volume, page. The keys minted here
    # are spelled IDENTICALLY ("PTS.S.4.16"), so the Pali original and its
    # Japanese translation meet on equal strings with no further fold.
    # Censused agreement (held trees, 2026-10-20): CBETA N's Dhs/Kv/Pp page
    # anchors number 264/627/74, exactly SuttaCentral's ds/kv/pp PTS token
    # counts; Nidd.1 (Mahāniddesa) 510 = mnd's 510.
    #
    # == Fold rules (censused against the held reference tree, a20fcb09)
    #
    # 23,734 pts-* tokens on 21,766 of 143,057 non-blank reference segments
    # (pli/ms only — the lzh Taishō and pra pdhp trees carry none):
    #
    # - "pts-vp-pli<vol>.<page>" (10,097) → "PTS.<siglum>.<vol>.<page>";
    #   the one page RANGE ("pts-vp-pli1.334-336", Vinaya) stays a range.
    # - "pts-vp-pli<page>" (3,577; the single-volume books — Dhs, Kv, Snp,
    #   Ud, Mil …) → "PTS.<siglum>.<page>".
    # - The Apadāna is two volumes paginated CONTINUOUSLY (Ap I pp. 1–338,
    #   Ap II pp. 339–615 — censused over tha-ap + thi-ap; CBETA writes
    #   PTS.Ap.1…615), so its vol.page tokens fold to "PTS.Ap.<page>".
    # - "pts-vp-pli<ed>ed<vol>.<page>" / "pts-vp-pli<ed>ed<page>" (1,350;
    #   SN I, Dhp, Vv, Pv, Bv, Cp — the books with two PTS editions of
    #   different pagination). The FIRST edition folds to the plain
    #   spelling ("PTS.S.1.154"); the second stays explicit
    #   ("PTS-ed2.S.1.332"). Established, not assumed (2026-10-20): CBETA
    #   N's anchors are the Nanden Daizōkyō's (Japanese, 1935–41; the
    #   Yuan Heng Temple canon translates it), which predates every second
    #   edition (Bv/Cp 1974, Vv/Pv 1977, Dhp 1994, SN I 1998); CBETA's own
    #   SN cross-reference cites "PTS [1884] 1991: I 154" (Feer) at the line
    #   its cref places on S.1.154; and page-for-page against the held
    #   trees N matches ed1 exactly — SN I pp. 1–240 (ed2 runs to 516), SN
    #   6.12/6.14 on 154/155 (ed2 332/335), Dhp vv. 100/200/300/400/423 on
    #   15/30/43/57/60 (ed2 28/56/84/112/118), Bv's chapter breaks and Cp
    #   pp. 73–103 (ed2 1–37). SuttaCentral carries only ed2 for Vv and Pv,
    #   which N (Vv pp. 1–84, Pv 3–68) does not follow — those stay apart.
    # - The Buddhavaṃsa is one volume in either edition; upstream writes it
    #   "…ed1.<page>" (volume 1) and CBETA "PTS.Bv.<page>", so the volume
    #   drops.
    # - NOT folded (they stay in the verbatim "refs" string, counted):
    #   "pts-vp-en…" (2,461 — Horner's English Book of the Discipline, not
    #   a Pali page), "pts-cs…" (6,155 — PTS section numbering in DN and
    #   the Vinaya, not a page), and AN's three-part "pts-vp-pli1.1.1" (94
    #   — the third number's meaning is not stated upstream; never guessed).
    # - VRI: every "vri<n>.<n>" token (17,589) rides "vri" verbatim — no
    #   other held source cites VRI, so there is nothing to fold toward.
    #
    # Expected full-corpus yield (dry-run of this module over the held tree,
    # joined passages only): 15,024 pts keys on 14,835 passages (94 AN
    # tokens unfolded), 17,589 vri tokens on 17,549 passages. Of the 14,058
    # distinct plain keys, 13,579 (96.6%) are spelled identically to a
    # CBETA N cref anchor (the ed1 fold added 400, 399 matching: SN I
    # 240/240, Dhp 60/60, Cp 31/31, Bv 68/69); the rest are Nett/Peṭ (no
    # N translation) and a few pages N does not anchor. 950 distinct
    # PTS-ed2 keys stay apart by design.
    #
    # Lives under adapters/ (the CuneiformConcordance rule): it shapes
    # parsed rows, so it rides only the suttacentral derivation closure.
    module PtsConcordance
      # Book path under the root tree (basket/collection[/book]) → PTS
      # siglum, CBETA's spelling where CBETA cites the book. Only books whose
      # reference files carry PTS page tokens are listed (censused).
      SIGLA = {
        "sutta/dn" => "D", "sutta/mn" => "M", "sutta/sn" => "S", "sutta/an" => "A",
        "sutta/kn/kp" => "Khp", "sutta/kn/dhp" => "Dhp", "sutta/kn/ud" => "Ud", "sutta/kn/iti" => "It",
        "sutta/kn/snp" => "Sn", "sutta/kn/vv" => "Vv", "sutta/kn/pv" => "Pv", "sutta/kn/thag" => "Th",
        "sutta/kn/thig" => "Thī", "sutta/kn/tha-ap" => "Ap", "sutta/kn/thi-ap" => "Ap", "sutta/kn/bv" => "Bv",
        "sutta/kn/cp" => "Cp", "sutta/kn/ja" => "Ja", "sutta/kn/mnd" => "Nidd.1", "sutta/kn/cnd" => "Nidd.2",
        "sutta/kn/ps" => "Paṭis", "sutta/kn/mil" => "Mil", "sutta/kn/ne" => "Nett", "sutta/kn/pe" => "Peṭ",
        "abhidhamma/ds" => "Dhs", "abhidhamma/vb" => "Vibh", "abhidhamma/dt" => "Dhātuk",
        "abhidhamma/pp" => "Pp", "abhidhamma/kv" => "Kv", "abhidhamma/ya" => "Yam",
        "vinaya" => "Vin"
      }.freeze

      # Sigla cited by page alone though upstream names a volume: the
      # Apadāna's two volumes share one continuous pagination; the
      # Buddhavaṃsa is a single volume (fold rules).
      PAGE_CITED = %w[Ap Bv].freeze

      # The PTS edition CBETA N's anchors follow in the two-edition books
      # (evidence in the module note): its keys take the plain spelling.
      CBETA_EDITION = "1"

      PAGE = /\d+(?:-\d+)?/
      VOLUME_PAGE = /\Apts-vp-pli(\d+)\.(#{PAGE})\z/
      PAGE_ONLY = /\Apts-vp-pli(#{PAGE})\z/
      EDITION_VOLUME_PAGE = /\Apts-vp-pli(\d+)ed(\d+)\.(#{PAGE})\z/
      EDITION_PAGE = /\Apts-vp-pli(\d+)ed(#{PAGE})\z/
      VRI = /\Avri\d+(?:\.\d+)*\z/

      module_function

      # The siglum for a root file's dir parts under its tree
      # (["sutta", "kn", "kp"], ["vinaya", "pli-tv-kd"], ["vinaya"]); nil
      # for a book that carries no PTS pages.
      def siglum(parts)
        return nil if parts.empty?
        return SIGLA["vinaya"] if parts.first == "vinaya"

        SIGLA[parts.first(3).join("/")] || SIGLA[parts.first(2).join("/")]
      end

      # One reference token → its concordance key, or nil (rule list in
      # the module note).
      def key(token, siglum:)
        return nil if siglum.nil?

        case token
        when VOLUME_PAGE then volume_page_key("PTS", siglum, Regexp.last_match(1), Regexp.last_match(2))
        when PAGE_ONLY then "PTS.#{siglum}.#{Regexp.last_match(1)}"
        when EDITION_VOLUME_PAGE
          volume_page_key(edition_prefix(Regexp.last_match(1)), siglum, Regexp.last_match(2), Regexp.last_match(3))
        when EDITION_PAGE then "#{edition_prefix(Regexp.last_match(1))}.#{siglum}.#{Regexp.last_match(2)}"
        end
      end

      def edition_prefix(edition)
        edition == CBETA_EDITION ? "PTS" : "PTS-ed#{edition}"
      end

      # A whole upstream reference string → { "pts" => [keys], "vri" =>
      # [tokens] }, each key present only when non-empty, token order kept.
      def split(refs, siglum:)
        tokens = refs.split(",").map(&:strip).reject(&:empty?)
        pts = tokens.filter_map { |token| key(token, siglum: siglum) }.uniq
        vri = tokens.grep(VRI).uniq
        { "pts" => pts, "vri" => vri }.reject { |_k, list| list.empty? }
      end

      def volume_page_key(prefix, siglum, volume, page)
        PAGE_CITED.include?(siglum) ? "#{prefix}.#{siglum}.#{page}" : "#{prefix}.#{siglum}.#{volume}.#{page}"
      end
    end
  end
end
