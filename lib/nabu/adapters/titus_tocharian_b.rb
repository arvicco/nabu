# frozen_string_literal: true

require_relative "titus_tocharian_parser"
require_relative "titus_tocharian_a"

module Nabu
  module Adapters
    # TITUS Tocharian B Corpus — the West Tocharian manuscripts TITUS
    # serves to MEMBERS ONLY (J. W. Goethe-Universität Frankfurt, Prof.
    # Jost Gippert). The public TITUS text index (texte/texte2.htm, read
    # 2026-10-12) links ONE frameset for three parts: the Berlin Turfan
    # texts (data entry P. Olivier, Chr. Schaefer, T. Tamai, K. Kupfer;
    # the THT preliminary edition) and the London and the (partial) Paris
    # collections (data entry P. Widmer, K. Kupfer, M. Peyrot) — at
    # titus.fkidg1.uni-frankfurt.de/texte/etcc/toch/tochb/tochb.htm, which
    # answers HTTP 401 with `WWW-Authenticate: Basic`.
    #
    # == Access: the credentials seam
    #
    # The registry row declares `credentials: titus`: the member user +
    # password (it ROTATES, with emailed notice) live in
    # local/config/credentials.yml, set through `bin/nabu creds set titus`.
    # A sync with nothing stored refuses before any network; a 401 to the
    # stored credential raises Credentials::Rejected naming the same
    # command. The fetch is the Tocharian A family's TitusFetch walk with
    # the credential riding as Basic auth.
    #
    # == The grant (by email, 2026-10-06)
    #
    # The owner's personal grant names "the Tocharian A and B texts of the
    # Berlin Turfan collection as TITUS presents them" — the titus-avestan
    # mechanisms verbatim (grant_required, availability blocked, license
    # class nc + the manifest credit). The frameset ALSO carries the
    # London/Paris parts on the same page chain; the scope ruling of
    # 2026-10-12 reads the grant corpus-level, so they parse in as txb
    # under the same terms.
    #
    # == The page chain (census 2026-10-12, all 4,349 pages)
    #
    # ONE "Next part" chain: Part No. 1–999 are tochbNNN.htm, 1000–4349
    # toch1000.htm … toch4349.htm. By collection — Berlin THT (parts
    # 1–3549; the four-digit pages continue the THT numbers, no overlap),
    # Berlin SHT (3550–3559, Tamai), London British Library IOL Toch.
    # (3560–4340), Paris Pelliot Koutchéen (4341–4349). The later labels
    # carry underscores, so the family reads anchor levels from the
    # headings (TitusTocharianParser, "Levels"). An unknown content lane or
    # a page with no keyable line still quarantines (ParseError) — loud,
    # never silent.
    class TitusTocharianB < TitusTocharianA
      SLUG = "titus-tocharian-b"
      LANGUAGE = "txb"

      # From the public TITUS index's own link (http there; https answers
      # the same 401, and the http host is never asked to carry the secret).
      ENTRY_URL = "https://titus.fkidg1.uni-frankfurt.de/texte/etcc/toch/tochb/tochb.htm"

      LICENSE = "personal grant, Gippert (by email, 2026-10-06, extending the 2026-07-23 " \
                "Avestan terms to the Tocharian A and B texts of the Berlin Turfan collection): " \
                "one retrieval, local personal research use only, no redistribution; TITUS and " \
                "the editors clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Tocharian B corpus (members area): Berlin Turfan " \
               "collection, data entry P. Olivier, Chr. Schaefer, T. Tamai, K. Kupfer (preliminary " \
               "edition); London and Paris collections, data entry P. Widmer, K. Kupfer, M. Peyrot."

      # The chain's page naming: "Part No." 1–999 are tochbNNN.htm, from
      # 1000 on the generator drops the "b" — toch1000.htm … toch4349.htm
      # (census 2026-10-12). One chain, one numbering; the frameset
      # (tochb.htm) never matches.
      PAGE_GLOB = "toch*.htm"
      PAGE_RE = /\Atoch(?:b\d+|\d{4,})\.htm\z/

      # The collections the chain walks, in order (census 2026-10-12 over
      # all 4,349 pages): Berlin THT (parts 1–3549), Berlin SHT (3550–3559),
      # London IOL (3560–4340), Paris PK (4341–4349).
      COLLECTIONS = %w[THT SHT BLK-IOL PK].freeze

      # The lane census (2026-10-12): `tob` the B transcription/syllabic
      # (c and the Paris `v` notation variants), `sbpl` the Sanskrit of the
      # bilinguals, `toa` the Tocharian A lines of five London manuscripts
      # (claimed xto, line by line). Still unclassified, so quarantining:
      # `iotk16` (one Berlin page) and the `ts` stem (two London pages).
      PARSER_PROFILE = TitusTocharianParser::Profile.new(
        anchor_prefix: COLLECTIONS.map { |c| "TochB_#{c}" }.freeze,
        lane_family: /\Aio(?<stem>tob|toa|sbpl)(?<syllabic>[xv]?)c?16\z/,
        lane_languages: { "tob" => :txb, "toa" => :xto, "sbpl" => :san }.freeze,
        primary_language: :txb
      )
      CORPUS_TITLE = "Tocharian B Corpus"

      # The catalogue-only rule: a manuscript heading with no page or line
      # heading below it (the labels carry underscores, so the A rule's
      # anchor-depth test cannot apply).
      MANUSCRIPT_ANCHOR = /NAME="TochB_(?:#{COLLECTIONS.map { |c| Regexp.escape(c) }.join('|')})_/
      DEEPER_ANCHOR = /<!Level [45]>/

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "TITUS Tocharian B Corpus",
          license: LICENSE,
          license_class: "nc",
          upstream_url: ENTRY_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # The probe HEADs the members entry page unauthenticated — a 401 there
      # is the gate answering, not an outage.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "tochb.htm entry (members only)", zip_url: ENTRY_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::TitusFetch::STATE_FILE
        )]
      end
    end
  end
end
