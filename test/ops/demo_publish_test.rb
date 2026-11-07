# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "yaml"
require "stringio"
require "nabu/ops/demo_publish"

module Ops
  # Nabu::Ops::DemoPublish — the LOCAL half of the demo-image rail
  # (`rake demo:publish`): the slice needs this box's full library, so
  # GitHub-hosted CI can never build the image; it only pulls and smokes it
  # (Smoke) and publishes server.json to the MCP Registry. Tests pin the
  # command assembly and the stdio smoke's protocol order; nothing here
  # runs docker.
  class DemoPublishTest < Minitest::Test
    P = Nabu::Ops::DemoPublish
    ROOT = File.expand_path("../..", __dir__)

    def with_project(version: "1.2.3", identifier: nil, census: true)
      Dir.mktmpdir("demo-publish") do |dir|
        root = File.join(dir, "repo")
        slice = File.join(dir, "slice")
        FileUtils.mkdir_p([root, slice])
        identifier ||= "#{P::IMAGE}:#{version}"
        server = { "name" => P::SERVER_NAME, "version" => version,
                   "packages" => [{ "registryType" => "oci", "identifier" => identifier }] }
        File.write(File.join(root, "server.json"), JSON.generate(server))
        File.write(File.join(slice, "demo-census.json"), "{}") if census
        yield root, slice
      end
    end

    # -- publish: the one buildx command ---------------------------------------

    def test_publish_argv_builds_the_demo_target_multi_arch_with_both_tags_and_pushes
      with_project do |root, slice|
        argv = P.publish_argv(root: root, slice: slice, nabu_version: "1.2.3")

        assert_equal %w[docker buildx build], argv.first(3)
        assert_equal "demo", argv[argv.index("--target") + 1]
        assert_equal "demo-slice=#{slice}", argv[argv.index("--build-context") + 1]
        assert_equal "linux/amd64,linux/arm64", argv[argv.index("--platform") + 1],
                     "an arm64-only image fails every amd64 host (GitHub runners, Render, Koyeb, most laptops)"
        tags = argv.each_index.select { |i| argv[i] == "-t" }.map { |i| argv[i + 1] }
        assert_equal ["#{P::IMAGE}:1.2.3", "#{P::IMAGE}:latest"], tags
        assert_includes argv, "--push"
        assert_equal root, argv.last, "the build context is the repo root"
      end
    end

    def test_publish_argv_takes_a_named_builder_and_custom_platforms
      with_project do |root, slice|
        argv = P.publish_argv(root: root, slice: slice, builder: "nabu-multi", platforms: ["linux/arm64"],
                              nabu_version: "1.2.3")

        assert_equal "nabu-multi", argv[argv.index("--builder") + 1]
        assert_equal "linux/arm64", argv[argv.index("--platform") + 1]
      end
    end

    # One version line (owner-ruled 2026-11-07): the demo image's number IS
    # the Nabu release number. A server.json left behind by the release
    # bump cannot build an image.
    def test_the_image_version_is_release_synced_to_the_checkout
      with_project(version: "1.2.3", identifier: "#{P::IMAGE}:1.2.3") do |root, slice|
        error = assert_raises(P::Refused) { P.publish_argv(root: root, slice: slice, nabu_version: "9.9.9") }
        assert_match(/release-synced/, error.message)
        assert_match(/1\.2\.3/, error.message)
        assert_match(/9\.9\.9/, error.message)
      end
    end

    def test_the_version_comes_from_server_json_and_must_match_its_oci_identifier
      with_project(version: "2.0.0", identifier: "#{P::IMAGE}:1.0.0") do |root, slice|
        error = assert_raises(P::Refused) { P.publish_argv(root: root, slice: slice) }
        assert_match(/1\.0\.0.*2\.0\.0|2\.0\.0.*1\.0\.0/, error.message)
      end
    end

    def test_an_unfinished_slice_is_refused_before_docker_runs
      with_project(census: false) do |root, slice|
        error = assert_raises(P::Refused) { P.publish_argv(root: root, slice: slice) }
        assert_match(/demo-census\.json/, error.message)
        assert_match(/rake demo:build/, error.message)
      end
    end

    def test_publish_runs_the_assembled_command_through_the_runner
      with_project do |root, slice|
        seen = []
        P.publish!(root: root, slice: slice, runner: ->(*argv) { seen << argv }, nabu_version: "1.2.3")

        assert_equal [P.publish_argv(root: root, slice: slice, nabu_version: "1.2.3")], seen
      end
    end

    def test_the_repo_server_json_names_the_published_image_and_label
      server = JSON.parse(File.read(File.join(ROOT, "server.json")))
      assert_equal P::SERVER_NAME, server.fetch("name")
      assert_equal "#{P::IMAGE}:#{server.fetch('version')}", server.dig("packages", 0, "identifier")
      assert_includes File.read(File.join(ROOT, "Dockerfile")),
                      %(io.modelcontextprotocol.server.name="#{P::SERVER_NAME}"),
                      "the registry verifies OCI ownership by this label"
      assert_operator server.fetch("description").length, :<=, 100,
                      "the MCP Registry refuses (422) a description over 100 characters"
    end

    # -- the release workflow's shape ---------------------------------------

    def workflow
      YAML.safe_load_file(File.join(ROOT, ".github", "workflows", "demo-release.yml"))
    end

    def test_the_release_workflow_never_runs_on_push_or_pull_request
      triggers = workflow.fetch(true).keys # YAML 1.1 reads the bare `on:` key as true
      assert_equal %w[release workflow_dispatch], triggers.sort
      assert_includes workflow.dig(true, "workflow_dispatch", "inputs", "jobs", "options"), "registry-publish",
                      "registry-publish must be dispatchable alone"
    end

    def test_registry_publish_has_oidc_and_every_action_is_sha_pinned
      jobs = workflow.fetch("jobs")
      assert_equal "write", jobs.dig("registry-publish", "permissions", "id-token")
      uses = jobs.values.flat_map { |job| job.fetch("steps").filter_map { |step| step["uses"] } }
      refute_empty uses
      uses.each { |ref| assert_match(/@[0-9a-f]{40}\z/, ref, "third-party actions pin a full commit SHA") }
      run = jobs.dig("registry-publish", "steps").filter_map { |step| step["run"] }.join("\n")
      assert_match(/mcp-publisher login github-oidc/, run)
      assert_match(%r{mcp-publisher publish \./server\.json}, run)
    end

    def test_the_image_smoke_initializes_first_through_the_shared_smoke
      steps = workflow.dig("jobs", "image-smoke", "steps").filter_map { |step| step["run"] }.join("\n")
      assert_match(/docker pull/, steps)
      assert_match(%r{script/demo-smoke}, steps)
    end

    # -- preflight: the owner's ONE command carries its own checks --------------

    def docker_config(auths: {}, helpers: nil)
      JSON.generate({ "auths" => auths }.tap { |c| c["credHelpers"] = helpers if helpers })
    end

    def test_ghcr_auth_is_read_from_the_docker_config
      assert P::Preflight.authed?(config: docker_config(auths: { "ghcr.io" => {} }))
      assert P::Preflight.authed?(config: docker_config(auths: { "https://ghcr.io" => {} }))
      assert P::Preflight.authed?(config: docker_config(helpers: { "ghcr.io" => "osxkeychain" }))
      refute P::Preflight.authed?(config: docker_config(auths: { "https://index.docker.io/v1/" => {} }))
      refute P::Preflight.authed?(config: nil)
      refute P::Preflight.authed?(config: "not json")
    end

    BUILDX_DOCKER_ONLY = <<~LS
      NAME/NODE     DRIVER/ENDPOINT   STATUS    BUILDKIT   PLATFORMS
      default*      docker
       \\_ default   \\_ default       running   v0.17.0    linux/arm64
    LS

    BUILDX_CONTAINER_CURRENT = <<~LS
      NAME/NODE       DRIVER/ENDPOINT     STATUS    BUILDKIT   PLATFORMS
      multi*          docker-container
       \\_ multi0     \\_ desktop-linux   running   v0.17.0    linux/arm64, linux/amd64
      default         docker
       \\_ default    \\_ default         running   v0.17.0    linux/arm64
    LS

    BUILDX_NABU_EXISTS = <<~LS
      NAME/NODE          DRIVER/ENDPOINT     STATUS     BUILDKIT   PLATFORMS
      default*           docker
       \\_ default       \\_ default         running    v0.17.0    linux/arm64
      nabu-demo          docker-container
       \\_ nabu-demo0    \\_ desktop-linux   inactive
    LS

    def test_builder_choice_is_nil_when_the_current_builder_is_docker_container
      assert_nil P::Preflight.builder_choice(BUILDX_CONTAINER_CURRENT),
                 "a current docker-container builder already emits multi-platform"
    end

    def test_builder_choice_reuses_an_existing_nabu_demo_builder
      assert_equal P::Preflight::BUILDER_NAME, P::Preflight.builder_choice(BUILDX_NABU_EXISTS)
    end

    def test_builder_choice_asks_for_a_create_on_a_classic_docker_only_box
      assert_equal :create, P::Preflight.builder_choice(BUILDX_DOCKER_ONLY),
                   "the plain docker driver on Apple Silicon is what produced an arm64-only public image"
    end

    def test_ensure_logs_in_and_creates_the_builder_only_when_needed
      calls = []
      builder = P::Preflight.ensure!(config: docker_config,
                                     login: -> { calls << :login },
                                     buildx_ls: -> { BUILDX_DOCKER_ONLY },
                                     create: ->(name) { calls << [:create, name] },
                                     log: StringIO.new)

      assert_equal P::Preflight::BUILDER_NAME, builder
      assert_equal [:login, [:create, P::Preflight::BUILDER_NAME]], calls
    end

    def test_ensure_is_a_no_op_when_authed_with_a_capable_builder
      calls = []
      builder = P::Preflight.ensure!(config: docker_config(auths: { "ghcr.io" => {} }),
                                     login: -> { calls << :login },
                                     buildx_ls: -> { BUILDX_CONTAINER_CURRENT },
                                     create: ->(name) { calls << [:create, name] },
                                     log: StringIO.new)

      assert_nil builder
      assert_empty calls
    end

    # -- post-push verification: the tags must be real multi-arch indexes ------

    def index_json(archs)
      JSON.generate("mediaType" => "application/vnd.oci.image.index.v1+json",
                    "manifests" => archs.map { |a| { "platform" => { "architecture" => a } } })
    end

    def test_verify_index_accepts_a_two_arch_index_and_ignores_attestation_manifests
      archs = P.verify_index!(index_json(%w[amd64 arm64 unknown]), image: "img:tag")

      assert_equal %w[amd64 arm64], archs
    end

    def test_verify_index_rejects_a_single_arch_index
      error = assert_raises(P::SmokeFailed) { P.verify_index!(index_json(%w[arm64]), image: "img:tag") }
      assert_match(/img:tag/, error.message)
      assert_match(/amd64/, error.message)
    end

    def test_verify_index_rejects_a_plain_single_platform_manifest
      raw = JSON.generate("mediaType" => "application/vnd.oci.image.manifest.v1+json", "config" => {})
      assert_raises(P::SmokeFailed) { P.verify_index!(raw, image: "img:tag") }
    end

    def test_verify_pushed_inspects_the_version_tag_and_latest
      with_project do |root, _slice|
        seen = []
        images = P.verify_pushed!(root: root, log: StringIO.new, nabu_version: "1.2.3",
                                  inspector: lambda { |image|
                                    seen << image
                                    index_json(%w[amd64 arm64])
                                  })

        assert_equal ["#{P::IMAGE}:1.2.3", "#{P::IMAGE}:latest"], seen
        assert_equal seen, images
      end
    end

    # -- smoke: initialize FIRST, then tools/list, then one real call -----------

    # A scripted stand-in for the docker stdio session.
    class FakeSession
      attr_reader :written

      def initialize(replies)
        @replies = replies
        @written = []
      end

      def write_line(line) = @written << JSON.parse(line)

      def read_line = JSON.generate(@replies.shift)
    end

    def good_replies
      [
        { "jsonrpc" => "2.0", "id" => 1,
          "result" => { "protocolVersion" => "2025-11-25", "serverInfo" => { "name" => "nabu", "version" => "9" } } },
        { "jsonrpc" => "2.0", "id" => 2,
          "result" => { "tools" => [{ "name" => "nabu_search" }, { "name" => "nabu_status" }] } },
        { "jsonrpc" => "2.0", "id" => 3,
          "result" => { "content" => [{ "type" => "text", "text" => "library ok" }], "isError" => false } }
      ]
    end

    def run_smoke(replies, **)
      session = FakeSession.new(replies)
      argv_seen = nil
      opener = lambda do |*argv, &blk|
        argv_seen = argv
        blk.call(session)
      end
      result = P::Smoke.run!(image: "img:tag", session: opener, **)
      [result, session, argv_seen]
    end

    def test_smoke_initializes_before_listing_tools
      result, session, = run_smoke(good_replies)

      assert_equal(%w[initialize notifications/initialized tools/list tools/call],
                   session.written.map { |m| m["method"] })
      refute session.written[1].key?("id"), "notifications/initialized is a notification (no id)"
      assert_equal "nabu_status", session.written[3].dig("params", "name")
      assert_equal %w[nabu_search nabu_status], result.tools
      assert_equal "nabu 9", result.server
      assert_equal "2025-11-25", result.protocol
    end

    def test_smoke_runs_docker_interactive_with_extra_args_before_the_image
      _, _, argv = run_smoke(good_replies, docker_args: ["--memory=512m"])

      assert_equal ["docker", "run", "-i", "--rm", "--memory=512m", "img:tag"], argv
    end

    def test_smoke_fails_loudly_on_an_rpc_error
      replies = good_replies
      replies[1] = { "jsonrpc" => "2.0", "id" => 2, "error" => { "code" => -32_600, "message" => "initialize first" } }
      error = assert_raises(P::SmokeFailed) { run_smoke(replies) }
      assert_match(%r{tools/list.*initialize first}, error.message)
    end

    def test_smoke_fails_on_an_empty_tool_list
      replies = good_replies
      replies[1] = { "jsonrpc" => "2.0", "id" => 2, "result" => { "tools" => [] } }
      assert_raises(P::SmokeFailed) { run_smoke(replies) }
    end

    def test_smoke_fails_when_the_status_call_reports_an_error
      replies = good_replies
      replies[2]["result"]["isError"] = true
      error = assert_raises(P::SmokeFailed) { run_smoke(replies) }
      assert_match(/nabu_status/, error.message)
    end

    def test_smoke_fails_on_a_mismatched_response_id
      replies = good_replies
      replies[0]["id"] = 7
      assert_raises(P::SmokeFailed) { run_smoke(replies) }
    end
  end
end
