# frozen_string_literal: true

require "test_helper"

module MCP
  # Unknown-argument rejection (contract bump 2026-11-10). MCP transports
  # do not enforce a schema's additionalProperties: false, so an argument
  # the tool does not declare used to be silently dropped — an
  # unimplemented filter no-op'd invisibly and the model read the
  # unfiltered page as the filtered one. ONE server-side check in
  # Tools#call, keyed off each tool's declared schema properties, refuses
  # it for every tool: the InvalidArguments isError path, naming the
  # unknown argument(s) and the valid ones so the caller self-corrects.
  class ToolsArgumentsTest < Minitest::Test
    def tools = Nabu::MCP::Tools.new(catalog: nil, fulltext: nil)

    def declared(name)
      Nabu::MCP::Tools::TOOLS.fetch(name).fetch(:input_schema).fetch(:properties).keys.map(&:to_s)
    end

    # The regression, per tool: every registered tool refuses an undeclared
    # argument before its handler runs (no corpus needed to prove it).
    Nabu::MCP::Tools::TOOLS.each_key do |name|
      define_method(:"test_#{name}_rejects_an_unknown_argument") do
        error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
          tools.call(name, { "no_such_filter" => "x" })
        end
        assert_match(/\A#{name} does not take no_such_filter — /, error.message)
        valid = declared(name)
        if valid.empty?
          assert_match(/it takes no arguments\z/, error.message)
        else
          assert_match(/valid arguments: #{Regexp.escape(valid.join(', '))}\z/, error.message,
                       "the refusal lists the tool's valid arguments so a model can self-correct")
        end
      end
    end

    def test_the_per_tool_regression_covers_all_fourteen_tools
      assert_equal 14, Nabu::MCP::Tools::TOOLS.size,
                   "a new tool is covered by the generated test above; bump this count with it"
    end

    def test_several_unknown_arguments_are_all_named_in_one_refusal
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) do
        tools.call("nabu_search", { "query" => "x", "zeta" => 1, "alpha" => 2 })
      end
      assert_match(/\Anabu_search does not take alpha, zeta — valid arguments: query, /, error.message)
    end

    def test_symbol_keys_are_matched_by_name
      error = assert_raises(Nabu::MCP::Tools::InvalidArguments) { tools.call("nabu_status", { bogus: 1 }) }
      assert_match(/nabu_status does not take bogus/, error.message)
    end

    def test_declared_arguments_pass_the_check
      # nil stores: the handlers answer their honest no-corpus note, proving
      # the check let every declared name through.
      { "nabu_status" => {},
        "nabu_show" => { "urn" => "urn:x", "parallel" => false, "include_restricted" => false },
        "nabu_search" => { "query" => "x", "source" => "pap", "axis" => "classical", "limit" => 3 },
        "nabu_concord" => { "query" => "x", "width" => 20 } }.each do |name, args|
        result = tools.call(name, args)
        assert_equal false, result.fetch(:isError), "#{name} #{args.inspect}"
      end
    end

    def test_the_server_maps_an_unknown_argument_to_an_is_error_result
      server = Nabu::MCP::Server.new(tools: tools)
      server.handle_line(JSON.generate({ jsonrpc: "2.0", id: 1, method: "initialize",
                                         params: { protocolVersion: Nabu::MCP::Server::PROTOCOL_VERSION,
                                                   capabilities: {}, clientInfo: { name: "t", version: "0" } } }))
      server.handle_line(JSON.generate({ jsonrpc: "2.0", method: "notifications/initialized" }))
      response = JSON.parse(server.handle_line(JSON.generate({
                                                               jsonrpc: "2.0", id: 2, method: "tools/call",
                                                               params: { name: "nabu_concord",
                                                                         arguments: { query: "x", source: "pap" } }
                                                             })))
      result = response.fetch("result")
      assert_equal true, result.fetch("isError")
      assert_match(/nabu_concord does not take source — valid arguments: query, lemma, /,
                   result.dig("content", 0, "text"))
    end
  end
end
