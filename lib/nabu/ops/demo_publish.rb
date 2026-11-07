# frozen_string_literal: true

require "json"
require_relative "../errors"
require_relative "../shell"

module Nabu
  module Ops
    # The demo-image distribution rail — the half that CANNOT run in
    # GitHub-hosted CI. The image bakes the demo slice (Nabu::DemoBuild,
    # `rake demo:build`), and building that slice needs this box's full
    # library, so the image build + push is ONE local command:
    #
    #   bundle exec rake demo:build      # → tmp/demo (DEMO_OUT overrides)
    #   bundle exec rake demo:publish    # buildx: :<version> + :latest, multi-arch, --push
    #
    # The version is server.json's — the one place it is written — and the
    # build is refused unless server.json's OCI identifier names exactly
    # that tag, so the MCP Registry entry (published from server.json by
    # .github/workflows/demo-release.yml) never points at an image tag that
    # was not pushed. The image is built for amd64 AND arm64: an
    # arm64-only image (what a plain build on Apple Silicon makes) fails to
    # pull on every amd64 host — GitHub's runners, Render, Koyeb, most
    # laptops.
    #
    # Smoke is the other half CI CAN run: pull the public image and speak
    # MCP to it over stdio — initialize FIRST (the server refuses
    # tools/list before it), the initialized notification, tools/list, then
    # one real tools/call (nabu_status) proving the baked library answers.
    # `rake demo:smoke` and script/demo-smoke (the workflow's
    # dependency-free entry point) both run it.
    #
    # Loads only the stdlib + Nabu::Shell, so script/demo-smoke runs on a
    # bare Ruby with no bundle.
    module DemoPublish
      IMAGE = "ghcr.io/arvicco/nabu-demo"
      SERVER_NAME = "io.github.arvicco/nabu-demo"
      PLATFORMS = %w[linux/amd64 linux/arm64].freeze
      SERVER_JSON = "server.json"
      CENSUS_FILE = "demo-census.json" # Nabu::DemoBuild::CENSUS_FILE (not loaded here)

      # A precondition failed before docker ran.
      class Refused < Nabu::Error; end

      # The image did not answer the MCP smoke correctly.
      class SmokeFailed < Nabu::Error; end

      # server.json's version, checked against its OCI package identifier
      # AND against the checkout's own release number (owner-ruled
      # 2026-11-07: ONE version line — the demo image's number IS the Nabu
      # release number; server.json bumps with CITATION.cff and
      # Nabu::VERSION in the release rail's bump commit, ops §12 step 2).
      def self.version(root:, nabu_version: Nabu::VERSION)
        server = JSON.parse(File.read(File.join(root, SERVER_JSON)))
        version = server.fetch("version")
        identifier = Array(server["packages"]).find { |pkg| pkg["registryType"] == "oci" }&.fetch("identifier", nil)
        expected = "#{IMAGE}:#{version}"
        unless identifier == expected
          raise Refused, "server.json version #{version} but its OCI identifier is #{identifier.inspect} " \
                         "(expected #{expected}) — bump both together"
        end
        if nabu_version && version != nabu_version
          raise Refused, "server.json says #{version} but this checkout is nabu #{nabu_version} — the image " \
                         "version is release-synced (one version line); bump server.json in the release's " \
                         "bump commit before publishing"
        end

        version
      end

      # The one buildx command: demo target, the slice as the named
      # `demo-slice` context, both tags, multi-arch, pushed.
      def self.publish_argv(root:, slice:, platforms: PLATFORMS, builder: nil, nabu_version: Nabu::VERSION)
        unless File.file?(File.join(slice, CENSUS_FILE))
          raise Refused, "#{slice} is not a finished demo slice (no #{CENSUS_FILE}) — run rake demo:build first"
        end

        version = version(root: root, nabu_version: nabu_version)
        argv = %w[docker buildx build]
        argv += ["--builder", builder] if builder
        argv + ["--platform", platforms.join(","), "--target", "demo",
                "--build-context", "demo-slice=#{slice}",
                "-t", "#{IMAGE}:#{version}", "-t", "#{IMAGE}:latest",
                "--push", root]
      end

      # Run the build + push. +runner+ receives the argv (default: streamed
      # through Nabu::Shell so buildx progress shows live).
      def self.publish!(root:, slice:, runner: nil, log: $stderr, **)
        argv = publish_argv(root: root, slice: slice, **)
        runner ||= ->(*cmd) { Nabu::Shell.stream(*cmd) { |line| log.print(line) } }
        runner.call(*argv)
        argv
      end

      # After the push, both tags must inspect as REAL multi-arch indexes —
      # a single-platform manifest is exactly the failure that shipped an
      # arm64-only public image. Returns the verified image refs.
      def self.verify_pushed!(root:, inspector: nil, log: $stderr, nabu_version: Nabu::VERSION)
        inspector ||= ->(image) { Nabu::Shell.run("docker", "buildx", "imagetools", "inspect", "--raw", image) }
        [version(root: root, nabu_version: nabu_version), "latest"].map do |tag|
          image = "#{IMAGE}:#{tag}"
          archs = verify_index!(inspector.call(image), image: image)
          log.puts "verified #{image}: #{archs.join('+')}"
          image
        end
      end

      # The raw manifest must be an index covering every requested platform
      # (attestation manifests report architecture "unknown" and are ignored).
      def self.verify_index!(raw_manifest, image:, platforms: PLATFORMS)
        data = JSON.parse(raw_manifest)
        archs = Array(data["manifests"]).filter_map { |m| m.dig("platform", "architecture") }.uniq - ["unknown"]
        missing = platforms.map { |p| p.split("/").last } - archs
        return archs if missing.empty?

        shape = archs.empty? ? "a single-platform manifest, not an index" : "an index of #{archs.join('+')} only"
        raise SmokeFailed, "#{image} pushed WITHOUT #{missing.join('+')} (#{shape}) — " \
                           "the builder did not emit multi-arch; re-run rake demo:publish"
      rescue JSON::ParserError => e
        raise SmokeFailed, "#{image}: manifest inspect returned non-JSON (#{e.message[0, 80]})"
      end

      # The preflight that makes `rake demo:publish` the owner's WHOLE act:
      # ghcr auth and a multi-platform builder are checked (and supplied)
      # inside the task, never handed over as setup incantations.
      module Preflight
        BUILDER_NAME = "nabu-demo"

        # ghcr.io credentials, read the way docker resolves them: an auths
        # entry (present even when a credsStore holds the secret) or a
        # per-registry credential helper.
        def self.authed?(config: default_config)
          return false unless config

          data = JSON.parse(config)
          return true if data.fetch("auths", {}).keys.any? { |key| key.include?("ghcr.io") }

          data.fetch("credHelpers", {}).key?("ghcr.io")
        rescue JSON::ParserError
          false
        end

        def self.default_config
          path = File.join(ENV.fetch("DOCKER_CONFIG", File.join(Dir.home, ".docker")), "config.json")
          File.file?(path) ? File.read(path) : nil
        end

        # Reads `docker buildx ls`: an existing BUILDER_NAME wins; a current
        # docker-container builder needs nothing (nil); the classic docker
        # driver alone (what produced the arm64-only image) asks for :create.
        def self.builder_choice(ls_output)
          builders = ls_output.lines.drop(1).filter_map do |line|
            next if line.start_with?(" ") || line.lstrip.start_with?("\\_")

            name, driver = line.split(/\s+/).first(2)
            next unless name

            { name: name.delete_suffix("*"), driver: driver.to_s, current: name.end_with?("*") }
          end
          return BUILDER_NAME if builders.any? { |row| row[:name] == BUILDER_NAME }
          return nil if builders.find { |row| row[:current] }&.fetch(:driver) == "docker-container"

          :create
        end

        # Ensure auth + a capable builder; returns the --builder name to pass
        # (nil when the current builder already suffices).
        def self.ensure!(config: default_config, log: $stderr,
                         login: method(:default_login), buildx_ls: method(:default_ls), create: method(:default_create))
          unless authed?(config: config)
            log.puts "ghcr.io credentials not found — running `docker login ghcr.io` " \
                     "(username: your GitHub login; password: a token with write:packages)"
            login.call
          end
          case (choice = builder_choice(buildx_ls.call))
          when :create
            log.puts "no multi-platform buildx builder — creating docker-container builder #{BUILDER_NAME}"
            create.call(BUILDER_NAME)
            BUILDER_NAME
          else
            choice
          end
        end

        def self.default_login
          Kernel.system("docker", "login", "ghcr.io") || raise(Refused, "docker login ghcr.io failed")
        end
        private_class_method :default_login

        def self.default_ls = Nabu::Shell.run("docker", "buildx", "ls")
        private_class_method :default_ls

        def self.default_create(name)
          Nabu::Shell.run("docker", "buildx", "create", "--name", name, "--driver", "docker-container", "--bootstrap")
        end
        private_class_method :default_create
      end

      # The MCP stdio smoke against a docker image.
      module Smoke
        PROTOCOL_VERSION = "2025-11-25" # Nabu::Mcp::Server::PROTOCOL_VERSION (not loaded here)
        STATUS_TOOL = "nabu_status"

        Result = Data.define(:server, :protocol, :tools, :status_text)

        # Runs the sequence; returns a Result or raises SmokeFailed.
        # +session+ opens the stdio session (default Nabu::Shell.duplex).
        def self.run!(image:, docker_args: [], session: nil)
          argv = ["docker", "run", "-i", "--rm", *docker_args, image]
          session ||= ->(*cmd, &blk) { Nabu::Shell.duplex(*cmd, &blk) }
          session.call(*argv) { |io| converse(io) }
        end

        def self.converse(io)
          init = call(io, 1, "initialize",
                      "protocolVersion" => PROTOCOL_VERSION, "capabilities" => {},
                      "clientInfo" => { "name" => "nabu-demo-smoke", "version" => "1" })
          io.write_line(JSON.generate("jsonrpc" => "2.0", "method" => "notifications/initialized"))
          tools = Array(call(io, 2, "tools/list", {})["tools"]).map { |tool| tool["name"] }
          raise SmokeFailed, "tools/list returned no tools" if tools.empty?

          status = call(io, 3, "tools/call", "name" => STATUS_TOOL, "arguments" => {})
          text = Array(status["content"]).filter_map { |part| part["text"] }.join("\n")
          raise SmokeFailed, "#{STATUS_TOOL} reported an error: #{text[0, 300]}" if status["isError"]

          info = init.fetch("serverInfo", {})
          Result.new(server: "#{info['name']} #{info['version']}", protocol: init["protocolVersion"],
                     tools: tools, status_text: text)
        end
        private_class_method :converse

        def self.call(io, id, method, params)
          io.write_line(JSON.generate("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params))
          reply = begin
            JSON.parse(io.read_line)
          rescue JSON::ParserError => e
            raise SmokeFailed, "#{method}: non-JSON on stdout (#{e.message[0, 120]})"
          end
          raise SmokeFailed, "#{method}: reply id #{reply['id'].inspect}, expected #{id}" unless reply["id"] == id
          raise SmokeFailed, "#{method}: #{reply.dig('error', 'message') || reply['error']}" if reply.key?("error")

          reply.fetch("result") { raise SmokeFailed, "#{method}: reply carries no result" }
        end
        private_class_method :call
      end
    end
  end
end
