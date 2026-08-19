# frozen_string_literal: true

require "test_helper"

module Adapters
  # P79-2 (Q35): every non-git source must declare an HONEST remote-probe
  # posture — the :git default ls-remotes the upstream URL, which reads a
  # permanent false "gone" for zip/file/crawl sources (the P78 Korean
  # family + achemenet shipped wired with exactly that gap, and the sweep
  # below found six older sources in the same state).
  class RemoteProbeDeclarationsTest < Minitest::Test
    REGISTRY = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))

    # The tripwire: an adapter that inherits the :git default must actually
    # fetch through git. The fetch METHOD's defining file is the honest
    # place to look (derge-kangyur/tengyur inherit a git-backed fetch from
    # the EsukhiaText base — the subclass file never mentions git).
    def test_every_git_strategy_source_actually_fetches_through_git
      offenders = REGISTRY.each_source.filter_map do |entry|
        next if entry.shelf?

        klass = entry.adapter_class
        next unless klass.remote_probe_strategy == :git
        next if klass.upstream_repo_urls.empty? # vendored/local — probed as a local tree

        file, = klass.instance_method(:fetch).source_location
        next if file.nil? || File.read(file).match?(/git_fetch!|GitFetch/)

        "#{entry.slug} (#{File.basename(file)})"
      end
      assert_empty offenders,
                   "non-git fetch paths inheriting the :git probe default — declare :http_zip " \
                   "targets (or liveness_only) instead: #{offenders.join(', ')}"
    end

    def test_every_http_zip_source_declares_probeable_targets
      REGISTRY.each_source.each do |entry|
        next if entry.shelf?

        klass = entry.adapter_class
        next unless klass.remote_probe_strategy == :http_zip

        targets = klass.http_probe_targets
        refute_empty targets, "#{entry.slug}: :http_zip with no targets probes nothing"
        targets.each do |target|
          assert target.zip_url || target.resolver,
                 "#{entry.slug}/#{target.label}: a target needs a zip_url or a resolver"
        end
      end
    end

    # -- the data.go.kr family (resolver targets: the atchFileId bumps on
    # -- every artifact replacement, so only probe-time resolution is honest)

    def test_sillok_declares_resolver_targets_per_dataset
      targets = Nabu::Adapters::Sillok.http_probe_targets

      assert_equal :http_zip, Nabu::Adapters::Sillok.remote_probe_strategy
      assert_equal %w[taejo-cheoljong gojong-sunjong], targets.map(&:state_subdir)
      targets.each do |target|
        assert_nil target.zip_url
        refute_nil target.resolver
        assert_equal Nabu::ZipFetch::STATE_FILE, target.state_file
      end
    end

    def test_the_single_zip_korean_sources_declare_one_resolver_target_each
      {
        Nabu::Adapters::Sjw => "15064218",
        Nabu::Adapters::Goryeosa => "15053637",
        Nabu::Adapters::GoryeosaJeoryo => "15115521",
        Nabu::Adapters::Bibyeonsa => "15053636"
      }.each do |klass, pk|
        assert_equal :http_zip, klass.remote_probe_strategy, klass.name
        targets = klass.http_probe_targets

        assert_equal 1, targets.size, klass.name
        target = targets.first

        assert_nil target.zip_url, klass.name
        refute_nil target.resolver, klass.name
        assert_equal "", target.state_subdir, klass.name
        assert_includes target.label, pk, klass.name
      end
    end

    def test_itkc_declares_one_resolver_target_per_registered_dataset
      targets = Nabu::Adapters::Itkc.http_probe_targets

      assert_equal :http_zip, Nabu::Adapters::Itkc.remote_probe_strategy
      assert_equal Nabu::Adapters::Itkc::DATASETS.map { |d| d[:pk] }, targets.map(&:state_subdir)
      targets.each { |target| refute_nil target.resolver }
    end

    # -- static-URL artifacts (URL-identity drift via the state file) --------

    def test_achemenet_declares_its_zenodo_artifact
      assert_equal :http_zip, Nabu::Adapters::Achemenet.remote_probe_strategy
      target = Nabu::Adapters::Achemenet.http_probe_targets.first

      assert_equal Nabu::Adapters::Achemenet::ARTIFACT_URL, target.zip_url
      assert_equal "", target.state_subdir
      assert_equal Nabu::ZipFetch::STATE_FILE, target.state_file
    end

    def test_the_file_fetch_sources_declare_their_dump_urls
      { Nabu::Adapters::Cigs => Nabu::Adapters::Cigs::DUMP_URL,
        Nabu::Adapters::Unikemet => Nabu::Adapters::Unikemet::DUMP_URL }.each do |klass, url|
        assert_equal :http_zip, klass.remote_probe_strategy, klass.name
        target = klass.http_probe_targets.first

        assert_equal url, target.zip_url, klass.name
        assert_equal Nabu::FileFetch::STATE_FILE, target.state_file, klass.name
      end
    end

    def test_fornsvenska_declares_one_target_per_part
      targets = Nabu::Adapters::Fornsvenska.http_probe_targets

      assert_equal :http_zip, Nabu::Adapters::Fornsvenska.remote_probe_strategy
      assert_equal Nabu::Adapters::Fornsvenska::PARTS, targets.map(&:state_subdir)
      targets.each do |target|
        assert_match(/\.xml\.bz2\z/, target.zip_url)
        assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
      end
    end

    def test_titus_avestan_declares_its_entry_page_with_the_titus_state_file
      assert_equal :http_zip, Nabu::Adapters::TitusAvestan.remote_probe_strategy
      target = Nabu::Adapters::TitusAvestan.http_probe_targets.first

      assert_equal Nabu::Adapters::TitusAvestan::ENTRY_URL, target.zip_url
      assert_equal Nabu::TitusFetch::STATE_FILE, target.state_file
    end

    def test_pleiades_declares_its_dump_url
      assert_equal :http_zip, Nabu::Adapters::Pleiades.remote_probe_strategy
      target = Nabu::Adapters::Pleiades.http_probe_targets.first

      assert_equal Nabu::Adapters::Pleiades::DUMP_URL, target.zip_url
      assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
    end

    # -- crawl fetchers with no state file: liveness only, honestly ----------

    def test_the_stateless_crawl_sources_declare_liveness_only_targets
      { Nabu::Adapters::Kitab => Nabu::Adapters::Kitab::CONTENTS_API,
        Nabu::Adapters::BurmanConcordance => Nabu::Adapters::BurmanConcordance::CSV_URL,
        Nabu::Adapters::Sefaria => Nabu::Adapters::Sefaria::INDEX_URL,
        Nabu::Adapters::Trismegistos => Nabu::Adapters::Trismegistos.manifest.upstream_url }.each do |klass, url|
        assert_equal :http_zip, klass.remote_probe_strategy, klass.name
        target = klass.http_probe_targets.first

        assert_equal url, target.zip_url, klass.name
        assert target.liveness_only, "#{klass.name}: no state file — drift must not pretend"
      end
    end

    # -- manual-drop sources: no unattended upstream, probed as local --------

    def test_trismegistos_geo_declares_no_probeable_upstream
      assert_empty Nabu::Adapters::TrismegistosGeo.upstream_repo_urls,
                   "a ManualDrop source is probed as a local tree, never ls-remoted"
    end
  end
end
