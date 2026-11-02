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

      # server.json's version, checked against its OCI package identifier.
      def self.version(root:)
        server = JSON.parse(File.read(File.join(root, SERVER_JSON)))
        version = server.fetch("version")
        identifier = Array(server["packages"]).find { |pkg| pkg["registryType"] == "oci" }&.fetch("identifier", nil)
        expected = "#{IMAGE}:#{version}"
        unless identifier == expected
          raise Refused, "server.json version #{version} but its OCI identifier is #{identifier.inspect} " \
                         "(expected #{expected}) — bump both together"
        end

        version
      end

      # The one buildx command: demo target, the slice as the named
      # `demo-slice` context, both tags, multi-arch, pushed.
      def self.publish_argv(root:, slice:, platforms: PLATFORMS, builder: nil)
        unless File.file?(File.join(slice, CENSUS_FILE))
          raise Refused, "#{slice} is not a finished demo slice (no #{CENSUS_FILE}) — run rake demo:build first"
        end

        version = version(root: root)
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
