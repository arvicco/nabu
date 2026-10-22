# frozen_string_literal: true

require "digest"
require_relative "errors"

module Nabu
  # The model-output shelf convention (architecture §16 "the
  # model-output convention") — the identity half: the cache key and the
  # versioned prompt files. Minted BEFORE the first paid-model producer so
  # nothing ad-hoc ships; every future model lane composes these seams with
  # Nabu::ModelShelf (the runs + outputs gateway), Nabu::ModelBudget (the
  # monthly cap) and Nabu::ModelCall (the per-call check order).
  #
  # == The key (FIXED — verified against two live implementations)
  #
  #   sha256("urn|tool|prompt_version|model")
  #
  # Every component is part of the identity: a new model or a bumped
  # prompt version is a NEW key, so the stale rows simply stop answering —
  # they are ORPHANED, never deleted (auditability: what a model said under
  # an older prompt stays on the shelf, censused by ModelShelf#orphans). A
  # component carrying the separator would make two recipes collide, so it
  # is refused rather than escaped.
  #
  # == Prompt templates are versioned FILES
  #
  #   config/prompts/<tool>/<version>.md
  #
  # Project definition (git-tracked, reviewable), one file per version,
  # never edited in place once a run used it — a wording change is a new
  # version file, and the producer names its version as a LITERAL
  # (`PROMPT_VERSION = "v2"`), so the bump is a visible code change. A
  # multi-stage producer gives each stage its own tool name (its own
  # prompt directory), so "stage" and "tool" are one identity.
  module ModelOutput
    SEPARATOR = "|"

    # Tool names (prompt directories) and version file stems.
    TOOL_NAME = /\A[a-z][a-z0-9-]*\z/
    VERSION_NAME = /\Av\d+(?:\.\d+)*\z/

    # A {{placeholder}} in a template.
    PLACEHOLDER = /\{\{\s*([a-z_][a-z0-9_]*)\s*\}\}/

    # A missing prompt file, a malformed tool/version name, or a render
    # with an unbound placeholder.
    class Error < Nabu::Error; end

    # One versioned prompt template. +text+ is the file verbatim — what a
    # run's config.json records per stage.
    Prompt = Data.define(:tool, :version, :path, :text) do
      def sha256 = Digest::SHA256.hexdigest(text)

      # Substitute {{name}} placeholders from +vars+ (string or symbol
      # keys). An unbound placeholder is an error — a prompt that silently
      # sends "{{text}}" to a paid model is money spent on nothing.
      def render(vars)
        lookup = vars.transform_keys(&:to_s)
        text.gsub(PLACEHOLDER) do
          name = Regexp.last_match(1)
          raise Error, "prompt #{tool}/#{version}: no value for {{#{name}}}" unless lookup.key?(name)

          lookup.fetch(name).to_s
        end
      end
    end

    module_function

    # The cache/identity key (class note). Raises ArgumentError on an
    # empty component or one carrying the separator.
    def key(urn:, tool:, prompt_version:, model:)
      parts = { urn: urn, tool: tool, prompt_version: prompt_version, model: model }
      parts.each do |name, value|
        raise ArgumentError, "model-output key: #{name} is empty" if value.to_s.empty?
        raise ArgumentError, "model-output key: #{name} carries '#{SEPARATOR}'" if value.to_s.include?(SEPARATOR)
      end
      Digest::SHA256.hexdigest(parts.values.join(SEPARATOR))
    end

    # Load config/prompts/<tool>/<version>.md (+prompts_dir+ is the
    # config's prompts_dir). Missing file → Error naming the path.
    def prompt(prompts_dir:, tool:, version:)
      raise Error, "prompt tool name #{tool.inspect} must match #{TOOL_NAME.source}" unless tool.to_s.match?(TOOL_NAME)
      unless version.to_s.match?(VERSION_NAME)
        raise Error, "prompt version #{version.inspect} must match #{VERSION_NAME.source}"
      end

      path = File.join(prompts_dir, tool, "#{version}.md")
      raise Error, "no prompt file #{path} — a prompt version is a file, never an inline string" unless File.file?(path)

      Prompt.new(tool: tool, version: version, path: path, text: File.read(path, encoding: "UTF-8"))
    end
  end
end
