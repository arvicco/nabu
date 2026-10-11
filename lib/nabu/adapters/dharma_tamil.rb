# frozen_string_literal: true

require "nokogiri"

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA Tamil-country epigraphy (P118-1): Task Force A of the DHARMA
    # project (ERC no. 809994, EFEO/CNRS/CEIAS) — the eleven tfa-* edition
    # repos on github.com/erc-dharma, 1,301 DHARMA_ edition files (live
    # census 2026-10-11): Pallava 482, Tamil Nadu varia 335, SII
    # selections 176, Tiruvāvaṭutuṟai 80, Cīrkāḻi 55, Pāṇḍya 54,
    # Koṭumpāḷūr 41, Uttiramērūr 26, Mēlappaḻuvūr 20, Tamil outside TN 20,
    # Cempiyaṉ Mahādevī 12. Romanized Tamil above all (tam-Latn), with the
    # Pallava Sanskrit/Prakrit charters, Telugu lines in Nāyaka-era grants
    # and one French slab (Saint-Paul de la Réunion, 1888).
    #
    # == Shape: the first MULTI-REPO DHARMA source
    #
    # Same parse contract as the five per-repo siblings (DharmaBase:
    # identity, the held dharma-epidoc family, the in-file licence
    # doctrine); what differs is acquisition. #fetch composes one
    # GitFetch per repo into canonical/dharma-tamil/<repo>/ the way
    # UniversalDependencies composes its treebanks — every repo prepared,
    # ONE breaker over all their deletions, then every repo merged — with
    # per-repo ledger pins. The repos are flat (editions at the root, the
    # pyu layout), so the sparse cone is a root-anchored no-cone pattern
    # set: /DHARMA_*.xml + README.md + LICENCE.txt. That excludes, by
    # construction, upstream's "~DHARMA_" drafts/retirements (a promotion
    # renames INTO the cone, a retirement out of it — the attic catches
    # the latter), tfa-sii's sii-corpus/ (the OCR'd printed SII volumes
    # 1–4 as non-TEI <doc> files, NOT editions) and its HTML renderings.
    #
    # == Out of the roster (live enumeration 2026-10-11)
    #
    # tfa-accalpuram (an empty texts/xml scaffold), tfa-pondicherry and
    # tfa-tiruvannamalai (readme-only stubs): zero editions today — a
    # roster line each when they fill. The separate south-indian-
    # inscriptions repo and every tfb-/tfc-/tfd-/mdt-/arie repo are other
    # sources' (or no source's) business.
    #
    # == Languages (full census of every file, 2026-10-11)
    #
    # Minted codes across 1,301 files: tam-Latn (1,140 editions), san-Latn
    # (116), pra-Latn (4, Pallava Prakrit charters), pli-Latn (1), fra-Latn
    # (1) as document codes; tel-Latn rides 13 passages inside Pallava
    # and Tiruvāvaṭutuṟai plates. Bare "tam" (5 editions: 3 Pallava, 2
    # SII) is upstream tag dirt over romanized text — aliased to tam-Latn.
    # eng (head/label captions), zho (the Quanzhou bilingual's gap-only
    # Chinese face) and kan-Latn (one SII Kannada signature line inside a
    # Tamil prose line) occur but never mint. Two TamilNadu editions
    # carry no xml:lang at all: the corpus is multilingual, so no default
    # claims them — they quarantine loudly (the nusantara posture).
    #
    # == License
    #
    # In-file <licence target> governs and rides metadata verbatim: CC
    # BY-SA 4.0 on 1,227 files, CC BY 4.0 on 2 (both are upstream's
    # encoding templates, skipped). 71 files carry NO <licence>: they
    # fall back on the repo's LICENCE.txt (CC BY 4.0 legal code, README
    # badge "licence-CC-BY"), recorded as REPO_LICENSE — never silent.
    # Class attribution throughout.
    #
    # == Aggressive mining (owner rule 2026-09-26) and its declared limits
    #
    # The headers carry NO origDate / origPlace / history / provenance
    # anywhere (census 2026-10-11: zero files; msIdentifier reads "as per
    # external metadata" — findspots and dates live in DHARMA's separate
    # metadata repos, a future join). What the headers DO carry is mined:
    # respStmt persNames → "editors"; the edition div's @rendition (the
    # DHARMA script classification "class:… maturity:…") verbatim →
    # "script_rendition" (the family's numeric "maturity" still rides
    # too); the revisionDesc's first @status → "revision_status"; the
    # repo → "corpus". DELIBERATE COARSENESS: the house-style titles carry
    # an attributed dating statement on ~979 files ("time of
    # Rājakesarivarman, year 9", "Śaka year 1589") — recorded VERBATIM as
    # "title_dating", never converted: regnal years need a ruled
    # South-Indian regnal table (the regnal_years.yml shape) and Śaka →
    # CE an epoch ruling; and the title's leading toponym is NOT minted
    # as a place (it is sometimes a monument — "Utayēntiram plates").
    class DharmaTamil < DharmaBase
      SLUG = "dharma-tamil"
      NAME = "DHARMA Tamil-country epigraphy (Task Force A)"
      CREDIT_CORPUS = "Task Force A, Tamil Nadu epigraphic corpora (Pallava, Pāṇḍya, " \
                      "South Indian Inscriptions, Tamil Nadu varia and the temple corpora)"
      ORG_URL = "https://github.com/erc-dharma"
      REPO_URL = ORG_URL # the manifest's upstream_url; per-repo urls below
      XML_DIR = ""

      # The Tamil-country INSCRIPTION edition repos holding editions
      # (gh api orgs/erc-dharma/repos, 2026-10-11).
      REPOS = %w[
        tfa-cempiyan-mahadevi-epigraphy
        tfa-cirkali-epigraphy
        tfa-kotumpalur-epigraphy
        tfa-melappaluvur-kilappaluvur-epigraphy
        tfa-pallava-epigraphy
        tfa-pandya-epigraphy
        tfa-sii-epigraphy
        tfa-tamil-outside-TN-epigraphy
        tfa-tamilnadu-epigraphy
        tfa-tiruvavatuturai-epigraphy
        tfa-uttiramerur-epigraphy
      ].freeze

      SPARSE = ["/DHARMA_*.xml", "/README.md", "/LICENCE.txt"].freeze

      LANGUAGES = %w[tam-Latn san-Latn pra-Latn tel-Latn pli-Latn fra-Latn].freeze
      ALIASES = { "tam" => "tam-Latn" }.freeze

      REPO_LICENSE = "repo-level CC BY 4.0 (no in-file grant)"

      # Upstream's own encoding templates (DHARMA_INSPallava00000_template,
      # DHARMA_INSTiruvavatuturai00000_template) wear the edition prefix.
      TEMPLATE_SUFFIX = "_template"

      # The attributed dating statements of the house-style titles.
      TITLE_DATING = /\b(?:time of [^,]+(?:, year [^,]+)?|Śaka(?: year)? [\d?]+(?:[–-]\d+)?)/

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: NAME,
          license: "per-file <licence> (CC BY-SA 4.0 on nearly all editions) governs, recorded " \
                   "verbatim per document; files without one fall back on the repo LICENCE.txt " \
                   "(CC BY 4.0), recorded as such — class attribution either way",
          license_class: "attribution",
          upstream_url: ORG_URL,
          parser_family: "dharma-epidoc",
          credit: "DHARMA — #{CREDIT_CORPUS} (ERC no. 809994, EFEO/CNRS; erc-dharma on " \
                  "GitHub). Cite the corpus and its editors wherever used."
        )
      end

      def self.upstream_repo_urls
        REPOS.map { |repo| "#{ORG_URL}/#{repo}" }
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        super do |ref|
          yield Nabu::DocumentRef.new(
            source_id: ref.source_id, id: ref.id, path: ref.path,
            metadata: ref.metadata.merge("repo" => File.basename(File.dirname(ref.path)))
          )
        end
      end

      def discovery_skips(workdir)
        skipped = xml_paths(workdir).reject { |path| edition_file?(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped.size, unrecognized: 0,
          notes: skipped.map { |path| "#{File.basename(path)}: #{skip_reason(path)}" }
        )
      end

      def parse(document_ref)
        base = super
        metadata = base.metadata.merge(header_metadata(document_ref.path))
        metadata["license"] ||= REPO_LICENSE
        document = Nabu::Document.new(
          urn: base.urn, language: base.language, canonical_path: base.canonical_path,
          title: base.title, metadata: metadata
        )
        base.passages.each { |passage| document << passage }
        document
      end

      def fetch(workdir, progress: nil, force: false)
        pulls = git_pulls(workdir, progress)
        pulls.each_value(&:prepare!)
        guard_mass_deletion!(workdir, pulls.values.flat_map(&:doomed_paths), force: force)
        pulls.each_value(&:complete!)
        shas = pulls.transform_values(&:head_sha)
        Nabu::FetchReport.new(sha: shas.values.last, fetched_at: Time.now,
                              notes: fetch_notes(shas, pulls),
                              repos: shas.to_h { |repo, sha| [repo_url_for(repo), sha] })
      rescue Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Seams for tests (the house local-git pattern).
      def repos = REPOS

      def repo_url_for(repo) = "#{ORG_URL}/#{repo}"

      def git_pulls(workdir, progress)
        repos.to_h do |repo|
          [repo, Nabu::GitFetch.new(
            repo_url: repo_url_for(repo), dir: File.join(workdir, repo),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, repo), progress: progress, sparse: SPARSE
          )]
        end
      end

      def fetch_notes(shas, pulls)
        notes = shas.map { |repo, sha| "#{repo}=#{sha}" }.join(" ")
        atticked = pulls.values.sum { |pull| pull.atticked.size }
        atticked.positive? ? "#{notes} · atticked #{atticked} upstream-deleted file(s)" : notes
      end

      def xml_paths(workdir)
        repos.flat_map { |repo| Dir.glob(File.join(workdir, repo, "*.xml")) }.sort
      end

      def edition_file?(path)
        super && !template?(path)
      end

      def template?(path)
        File.basename(path, ".xml").end_with?(TEMPLATE_SUFFIX)
      end

      def skip_reason(path)
        template?(path) ? "upstream encoding template" : "not a DHARMA_ edition file"
      end

      # The header facts the family parser does not carry (class note).
      def header_metadata(path)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"))
        doc.remove_namespaces!
        title = doc.at_xpath("//teiHeader//titleStmt/title")&.text.to_s.gsub(/\s+/, " ")
        {
          "corpus" => File.basename(File.dirname(path)),
          "editors" => editors(doc),
          "script_rendition" => doc.at_xpath('//body//div[@type="edition"]/@rendition')&.value,
          "revision_status" => doc.at_xpath("//revisionDesc/change[@status][1]/@status")&.value,
          "title_dating" => title.scan(TITLE_DATING)
        }.reject { |_, value| value.nil? || value.empty? }
      end

      def editors(doc)
        doc.xpath("//teiHeader//titleStmt/respStmt/persName").filter_map do |person|
          name = Normalize.nfc(person.text.gsub(/\s+/, " ").strip)
          name.empty? ? nil : name
        end.uniq
      end
    end
  end
end
