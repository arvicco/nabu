# frozen_string_literal: true

require_relative "test_helper"

# `nabu layer` — the core-layers front door. The dates command reports its
# elapsed time through the shared DurationFormat helper; the subcommand
# class once lacked the mixin, so the summary line raised AFTER the
# re-projection ran — and Sequel's paged_each transaction rolled the whole
# refresh back with it. The pin here is the mixin, not the formatting.
class LayerCommandTest < Minitest::Test
  def test_layer_cli_formats_durations_for_its_summary_lines
    cli = Nabu::LayerCLI.new
    assert_respond_to cli, :format_duration
    assert_equal "1m01s", cli.format_duration(61)
  end
end
