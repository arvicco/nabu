# frozen_string_literal: true

module Nabu
  module Adapters
    # Dating for the Statutes of the Realm (P160-7): every BHO act title
    # opens with the reign and the session label of Raithby's own
    # chronological table — "Charles II, 1664 & 1665: An Act …" — and the
    # vol. 7 titles (William III) close with the statute roll's regnal
    # citation — "[Chapter VI. Rot. Parl. 12 § 13 Gul. III. p. 1. n. 6.]".
    # Both are read to a typed CE envelope (the MetadataDates :structured
    # "date" hash); the asset carries no finer date (no assent day).
    #
    # == The session label (all three volumes)
    #
    # Census 2026-11-05 over all 656 act rows: single years ("1625"),
    # ampersand pairs ("1664 & 1665") and Old Style/New Style pairs
    # ("1695-6"). The years are LEGAL years (Old Style, the year turning on
    # 25 March): a session headed with one year Y opened in legal year Y and
    # its acts may have received assent in Jan–Mar of New Style Y+1, so a
    # single year reads [Y, Y+1] (3 Car. I: opened 17 March 1627/8, the
    # Petition of Right passed June 1628 — headed "1627"). A pair already
    # names both calendar years and reads [Y1, Y2]. The lower bound never
    # precedes the reign's first year (1 W. & M., the Convention of
    # February 1689, is headed "1688"). One stated exception: the Long
    # Parliament's 16 Car. I session opened 3 November 1640 and royal
    # assents ran into 1642 (the Clerical Disabilities Act, February 1642) —
    # "Charles I, 1640" reads [1640, 1642].
    #
    # == The regnal citation (vol. 7 only)
    #
    # William III's regnal year N runs 13 Feb (1688+N) – 12 Feb (1689+N),
    # counted from the joint accession and continued after Mary's death
    # (28 Dec 1694). A session cited N (or N & M) opened in that regnal
    # year and may have given assent through the following one: the
    # citation reads [1688+N, 1690+M]. The rekeyed citations carry slips
    # ("12 § 13", "12 £ 13", "7&7") — the separator is read loosely, the
    # numbers verbatim ("8c9" — a c keyed for the ampersand — included).
    #
    # == Combining the two
    #
    # The label is the finer claim and stands when the citation's envelope
    # contains it. When they disagree, NEITHER is picked: the envelope is
    # their union and the date carries "conflict" => true. The live case:
    # BHO heads the 20 acts of 11 Will. III (session 16 Nov 1699 – 11 Apr
    # 1700) "1698-9", beside the roll's own "11 Gul. III". Per the BHO
    # editor (by email, 2026-11-10) this is NOT a transcription slip and
    # will not change: BHO reproduces the official Statutes of the Realm
    # print as-is, and the official print's years (confirmed by the
    # Chronological Table of the Statutes) differ from the unofficial
    # collections (Ruffhead/Pickering head the same acts "A.D. 1700,
    # 11 & 12 Will. III") — regnal dating is inherently ambiguous
    # (sessions span regnal years; an act has four defensible in-force
    # dates; the 25 Mar → 1 Jan new-year change; shifting prorogation
    # semantics). The union envelope is therefore the permanent honest
    # treatment, not a wait-for-upstream-fix: [1698, 1701] contains the
    # truth under every reckoning. Do not re-report this upstream.
    #
    # The vol. 5/6 titles (Charles I – William and Mary) carry no regnal
    # citation (their "[Chapter I. Rot. Parl. nu. 1.]" names roll numbers
    # only); their acts' regnal years live only in the body text and in
    # the chronological-table pages, neither of which is read here.
    module StatutesRealmDating
      Heading = Data.define(:reign, :session, :rest)

      # Reign → [first year an act can carry, last year a session can open
      # in]. Charles II's regnal years are reckoned from 30 Jan 1649, but
      # no act precedes the Restoration (1660), so 1660 is the floor here.
      REIGNS = {
        "Charles I" => [1625, 1649],
        "Charles II" => [1660, 1685],
        "James the Second" => [1685, 1688],
        "William and Mary" => [1689, 1694],
        "William III" => [1689, 1702]
      }.freeze

      # Labels whose envelope is stated rather than derived:
      # - the Long Parliament session (above) — assents into 1642;
      # - "William III, 1698-9": the OFFICIAL print's own heading for the
      #   session of 16 Nov 1699 – 11 Apr 1700, reproduced as-is by BHO
      #   policy (see the module comment); 20 of its 25 rows cite the
      #   roll's "11 Gul. III", so the two official claims span years and
      #   this envelope covers both, never a pick — the cited rows still
      #   meet their citation in #date.
      SESSION_ENVELOPES = {
        ["Charles I", "1640"] => [1640, 1642],
        ["William III", "1698-9"] => [1698, 1700]
      }.freeze

      HEADING = /\A(#{REIGNS.keys.map { |reign| Regexp.escape(reign) }.join('|')}),\s*
                 (\d{4}(?:-\d{1,2}|\s*&\s*\d{4})?)\s*:?\s*(\S.*)\z/mx

      # "12 & 13 Gul. III" and the rekeying slips (§, £, missing spaces).
      CITATION = /(\d{1,2})(?:\s*[&§£c]\s*(\d{1,2}))?\s*Gul\.\s*III/

      # William III's regnal year 1 opened 13 February 1689.
      WILLIAM_III_EPOCH = 1688

      module_function

      def heading(title)
        match = HEADING.match(title.to_s.strip) or return nil

        Heading.new(reign: match[1], session: match[2].gsub(/\s+/, " "), rest: match[3])
      end

      # "1695-6" → [1695, 1696]; "1664 & 1665" → [1664, 1665]; "1625" → [1625, 1625].
      def session_years(session)
        first = Integer(session[/\A\d{4}/], 10)
        tail = session[/(?:-|&\s*)(\d+)\z/, 1]
        return [first, first] if tail.nil?

        last = tail.length == 4 ? Integer(tail, 10) : Integer(first.to_s[0, 4 - tail.length] + tail, 10)
        [first, last]
      end

      def label_envelope(reign:, session:)
        floor, ceiling = REIGNS.fetch(reign) { raise ArgumentError, "unknown reign #{reign.inspect}" }
        first, last = session_years(session)
        unless first.between?(floor - 1, ceiling)
          raise ArgumentError, "session #{session.inspect} falls outside the reign of #{reign} (#{floor}–#{ceiling})"
        end

        envelope = SESSION_ENVELOPES.fetch([reign, session]) { [first, first == last ? last + 1 : last] }
        [[envelope.first, floor].max, envelope.last]
      end

      # The roll's regnal citation in a William III title, or nil.
      def regnal(title)
        heading = heading(title)
        return nil unless heading&.reign == "William III"

        match = CITATION.match(heading.rest) or return nil
        first = Integer(match[1], 10)
        last = match[2] ? Integer(match[2], 10) : first
        citation = match[2] ? "#{first} & #{last} Gul. III" : "#{first} Gul. III"
        { "citation" => citation, "years" => [first, last],
          "not_before" => WILLIAM_III_EPOCH + first, "not_after" => WILLIAM_III_EPOCH + last + 2 }
      end

      # The MetadataDates :structured "date" hash for an act title, or nil.
      def date(title)
        heading = heading(title) or return nil
        not_before, not_after = label_envelope(reign: heading.reign, session: heading.session)
        raw = "#{heading.reign}, #{heading.session}"
        regnal = regnal(title)
        return { "not_before" => not_before, "not_after" => not_after, "raw" => raw } if regnal.nil?

        raw = "#{raw} · Rot. Parl. #{verbatim_citation(heading.rest)}"
        if not_before >= regnal["not_before"] && not_after <= regnal["not_after"]
          return { "not_before" => not_before, "not_after" => not_after, "raw" => raw }
        end

        { "not_before" => [not_before, regnal["not_before"]].min,
          "not_after" => [not_after, regnal["not_after"]].max, "raw" => raw, "conflict" => true }
      end

      def verbatim_citation(rest)
        rest[/\d{1,2}(?:\s*[&§£c]\s*\d{1,2})?\s*Gul\.\s*III/]
      end
    end
  end
end
