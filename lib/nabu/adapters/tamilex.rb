# frozen_string_literal: true

require_relative "tamilex_tei_parser"

module Nabu
  module Adapters
    # TAMILEX — critical editions of the classical Tamil corpus (P121-3):
    # Universität Hamburg's Academies'-Programme project (Prof. Eva Wilden,
    # Jean-Luc Chevillard), publishing one GitHub repo per work under the
    # UHH-Tamilex org — the Caṅkam anthologies (Kuṟuntokai, Naṟṟiṇai,
    # Akanāṉūṟu, Puṟanāṉūṟu, Aiṅkuṟunūṟu, Kalittokai, Patiṟṟuppattu,
    # Paripāṭal, Pattuppāṭṭu), the Tirukkuṟaḷ, the epics (Cilappatikāram,
    # Maṇimēkalai, Peruṅkatai), the grammars and poetics (Tolkāppiyam,
    # Naṉṉūl, Tamiḻneṟi Viḷakkam, Taṇṭiyalaṅkāram, Puṟapporuḷ
    # Veṇpāmālai), the Tivākaram lexicon and the devotional canons
    # (Nālāyirat Tivviyap Pirapantam, the Eleventh Tirumuṟai). ISO 15919
    # romanized Tamil (tam-Latn) with parallel English; the per-word
    # wordsplit layer loads as GOLD tokens (TamilexTeiParser).
    #
    # == Roster (live enumeration of the org, 2026-10-12)
    #
    # 21 text-edition repos, 7,849 root XML files. OUT: the tooling and
    # study repos (bookbinding, collocations, KT-collocations, lib,
    # poemcheck, rawcorpus, studies, testing, workshop, workshop2025,
    # CompPhil2026), `lexicon` (the project's dictionary in progress — a
    # dictionary-shelf matter, not a text edition) and Cirupanarruppatai
    # (an empty scaffold: stylesheet + lib submodule, no edition yet — a
    # roster line when it fills).
    #
    # == Fetch
    #
    # One sparse GitFetch per repo into canonical/tamilex/<repo>/ the way
    # DharmaTamil composes its tfa-* repos: every repo prepared, ONE
    # breaker over all their deletions, then every repo merged; per-repo
    # ledger pins. The repos are flat (editions at the root), so the cone
    # is root-anchored: /*.xml + the readme. Out by construction: the
    # wordindex.db/html builds, .docx drafts, the lib submodule, and the
    # witness/manuscript/alignment subtrees (mss/, witnesses/,
    # alignments/ — diplomatic transcriptions behind the apparatus, a
    # separate parse shape). Nothing is materialized beside the clones.
    #
    # == Identity (FROZEN minting)
    #
    #   urn:nabu:tamilex:<file stem, NFC>     (…:KT1, …:TVM1.8.2, …:NaṉC001)
    #   passage: <urn>:<xml:id> | <urn>:<text n>.<block ordinal>
    #
    # Stems are upstream's own sigla and unique across the whole roster
    # (census 2026-10-12, the skipped files aside). Should a stem ever
    # appear in two repos, the first in roster order keeps the urn and the
    # other is a censused skip — the urn never forks.
    #
    # == Discovery skips (censused, never silent)
    #
    # Upstream's templates and scratch files (a leading "_" or ".", or
    # "template" in the stem — _KTSAMPLE, poem-template, the bare ".xml"),
    # the non-edition aggregates (witnesses.xml — a bare listWit;
    # wordindex.xml — a generated word index) and Tamiḻneṟi Viḷakkam's
    # Ed.xml (the base text the per-verse TNV*ed.xml files cite as
    # corresp="#Ed": the same 25 verses re-split, so ingesting it would
    # double every verse and its gold tokens). Files without the .xml
    # extension are not discovered at all (NalayiratTivviyapPirapantam's
    # "TVM1.2.2xml").
    #
    # == License
    #
    # CC BY-NC-SA 4.0, stated by the TAMILEX maintainers by email,
    # 2026-10-12; the repositories carry no license file yet (one is
    # pending upstream). Class nc.
    #
    # == Aggressive mining and its declared limits
    #
    # Mined: title → work/number/poet/section, editors with roles, the
    # witness list verbatim, the commentators and their source editions,
    # the work facet. NO header carries a composition date or place
    # (census 2026-10-12) — the years inside witness descriptions are
    # manuscript and printed-edition years, recorded verbatim, never
    # converted into a dating of the work; Peruṅkatai's
    # publicationStmt/date (2023) is the digital edition's own year and is
    # not carried. The colophons' tiṇai/tuṟai stay passage prose (see the
    # parser note).
    class Tamilex < Nabu::Adapter
      SLUG = "tamilex"
      ORG_URL = "https://github.com/UHH-Tamilex"

      # The text-edition repos (gh api users/UHH-Tamilex/repos, 2026-10-12).
      REPOS = %w[
        Ainkurunuru Akananuru Cilappatikaram Kalittokai Kuruntokai Manimekalai
        NalayiratTivviyapPirapantam Nannul Narrinai Paripatal PatinoranTirumurai
        Patirruppattu Pattuppattu perunkatai Purananuru PurapporulVenpamalai
        TamilneriVilakkam Tantiyalankaram Tirukkural Tivakaram Tolkappiyam
      ].freeze

      SPARSE = ["/*.xml", "/README.md", "/readme.md"].freeze

      SCRATCH = /\A[_.]|template/i
      AGGREGATES = %w[witnesses wordindex].freeze
      EXCLUDED = {
        "TamilneriVilakkam/Ed.xml" =>
          "the base text the per-verse TNV*ed.xml editions cite (corresp=\"#Ed\") — " \
          "the same verses re-split; ingested through the per-verse files"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "TAMILEX — critical editions of the classical Tamil corpus (Universität Hamburg)",
        license: "CC BY-NC-SA 4.0, stated by the TAMILEX maintainers by email, 2026-10-12 " \
                 "(the repositories carry no license file yet; one is pending upstream)",
        license_class: "nc",
        upstream_url: ORG_URL,
        parser_family: "tamilex-tei",
        credit: "TAMILEX (Universität Hamburg) — Prof. Eva Wilden, Jean-Luc Chevillard and the " \
                "project of the Academies' Programme. Cite the editions and their translators " \
                "wherever used."
      )

      def self.manifest = MANIFEST

      def self.upstream_repo_urls
        REPOS.map { |repo| "#{ORG_URL}/#{repo}" }
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir).each { |entry| yield entry[:ref] if entry[:ref] }
      end

      def discovery_skips(workdir)
        notes = census(workdir).filter_map { |entry| entry[:skip] }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        repo = document_ref.metadata["repo"] || File.basename(File.dirname(document_ref.path))
        TamilexTeiParser.new.parse(document_ref.path, urn: document_ref.id, metadata: { "repo" => repo })
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

      # One entry per root XML file across the roster, in roster order:
      # { ref: } for an admitted edition, { skip: note } otherwise.
      def census(workdir)
        holders = {}
        repos.flat_map do |repo|
          Dir.glob(File.join(workdir, repo, "*.xml"), File::FNM_DOTMATCH).sort.map do |path|
            entry(repo, path, holders)
          end
        end
      end

      def entry(repo, path, holders)
        name = File.basename(path)
        relative = "#{repo}/#{name}".unicode_normalize(:nfc)
        reason = skip_reason(relative, File.basename(name, ".xml"))
        return { skip: "#{relative}: #{reason}" } if reason

        stem = File.basename(name, ".xml").unicode_normalize(:nfc)
        if (holder = holders[stem])
          return { skip: "#{relative}: stem also held by #{holder} — the first in roster order keeps the urn" }
        end

        holders[stem] = repo
        { ref: Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{stem}",
                                     path: File.expand_path(path),
                                     metadata: { "repo" => repo, "repo_path" => relative }) }
      end

      def skip_reason(relative, stem)
        return EXCLUDED[relative] if EXCLUDED.key?(relative)
        return "upstream template or scratch file" if stem.empty? || stem.match?(SCRATCH)
        return "not an edition (#{stem}.xml is a generated aggregate)" if AGGREGATES.include?(stem)

        nil
      end
    end
  end
end
