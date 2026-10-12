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
    # London/Paris parts; whether those pages ride the same chain, and
    # whether the grant's Berlin wording covers them, is for the first
    # authenticated sync's census to put before the owner — nothing here
    # assumes either way.
    #
    # == PROVISIONAL constants (no B page has been seen)
    #
    # Every page-shape constant below is the Tocharian A census carried
    # over by analogy, NOT a B observation: the page pattern (tochbNNN.htm),
    # the anchor prefix (TochB_THT), the lane stem (`tob` → txb, with the
    # bilinguals' `sbpl` → san) and the catalogue-only anchors. The first
    # authenticated sync verifies them: it must census the page names the
    # chain actually reaches, the <A NAME> anchor prefix(es) — the London/
    # Paris parts will not be THT numbers — and every `io…16` lane id. A
    # wrong guess fails LOUD, never silently: an unknown content lane or a
    # page with no keyable line quarantines (ParseError), and a page name
    # outside PAGE_RE is never discovered. No parse fixtures exist until
    # those real pages are cut (local/fixtures/titus-tocharian-b/).
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

      # PROVISIONAL (see the class note): the A family's page naming.
      PAGE_GLOB = "tochb*.htm"
      PAGE_RE = /\Atochb\d+\.htm\z/

      # PROVISIONAL (see the class note): the A profile's shape with the B
      # stem; the first authenticated sync's lane census replaces it.
      PARSER_PROFILE = TitusTocharianParser::Profile.new(
        anchor_prefix: "TochB_THT",
        lane_family: /\Aio(?<stem>tob|sbpl)(?<syllabic>x?)c?16\z/,
        lane_languages: { "tob" => :txb, "sbpl" => :san }.freeze,
        primary_language: :txb
      )
      CORPUS_TITLE = "Tocharian B Corpus"

      # PROVISIONAL: the catalogue-only rule under the B anchor prefix.
      MANUSCRIPT_ANCHOR = /NAME="TochB_THT_[^_"]+"/
      DEEPER_ANCHOR = /NAME="TochB_THT_[^_"]+_[^"]+"/

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
