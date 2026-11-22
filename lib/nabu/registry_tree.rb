# frozen_string_literal: true

require "yaml"

module Nabu
  # The split-registry reader (P185): the two per-source registries —
  # config/sources/ (the source registry) and config/postures/ (the
  # core-layer posture record) — live as ONE FILE PER SLUG,
  # <dir>/<slug>.yml, instead of two monoliths that every concurrent
  # packet conflicted on.
  #
  # A registry PATH may name either shape, and every reader goes through
  # this seam so both parse to the identical Ruby object:
  #
  # - a FILE (the pre-split monolith shape — still how test fixtures and
  #   redirected trees write a small registry): read verbatim, exactly as
  #   before (missing or empty file = an empty mapping);
  # - a DIRECTORY (the shipped shape): every <slug>.yml is read in SORTED
  #   SLUG ORDER (by slug, not by filename — "a-b.yml" byte-sorts before
  #   "a.yml" while "a" < "a-b"), and the per-file mappings union into
  #   the one mapping the monolith used to parse to. The source registry
  #   was ruled alphabetic (owner, 2026-09-27: file order IS processing
  #   order), so the sorted union is order-identical to it.
  #
  # Header files: a file whose name starts with "_" (config/sources/
  # _header.yml carries the field-by-field schema notes and the
  # next-source template that headed the monolith) is DOCUMENTATION —
  # it must be comment-only, and one that parses to data is refused
  # (an entry added there would otherwise be silently ignored).
  #
  # The guards replace YAML's silent duplicate-key drop (the monolith's
  # standing hazard — a second `acd:` key quietly won): each slug file
  # must define EXACTLY ONE slug, spelled as its filename, on exactly one
  # key line; two files can never claim one slug; a *.yaml stray is
  # refused rather than skipped. Every violation raises
  # Nabu::ValidationError naming the file.
  #
  # +wrapper+: the postures record nests its rows under a top-level
  # `sources:` key, and each split file keeps that wrapper (so every
  # file is itself a valid postures file, byte-cut from the monolith);
  # the union is then returned under the same wrapper.
  module RegistryTree
    HEADER_PREFIX = "_"
    EXTENSION = ".yml"

    module_function

    def exist?(path)
      File.file?(path.to_s) || File.directory?(path.to_s)
    end

    # The parsed mapping (a Hash) — see the module comment for the two
    # shapes and the guards.
    def load(path, wrapper: nil)
      path = path.to_s
      return load_directory(path, wrapper: wrapper) if File.directory?(path)
      return {} unless File.exist?(path)

      YAML.safe_load_file(path) || {}
    end

    # The registry's TEXT (readers that mine comments, e.g. the dossier
    # scaffolder): a file's content, or a directory's header files then
    # slug files in load order, joined by one blank line — the monolith's
    # own layout.
    def text(path)
      path = path.to_s
      return File.exist?(path) ? File.read(path, encoding: "UTF-8") : "" unless File.directory?(path)

      files = header_files(path) + slug_files(path).map(&:last)
      files.map { |file| File.read(file, encoding: "UTF-8") }.join("\n")
    end

    # [[slug, path], ...] in sorted slug order (headers excluded).
    def slug_files(dir)
      entries(dir).reject { |name| name.start_with?(HEADER_PREFIX) }
                  .map { |name| [File.basename(name, EXTENSION), File.join(dir, name)] }
                  .sort_by(&:first)
    end

    def header_files(dir)
      entries(dir).select { |name| name.start_with?(HEADER_PREFIX) }.sort.map { |name| File.join(dir, name) }
    end

    def entries(dir)
      names = Dir.children(dir).reject { |name| name.start_with?(".") }
      stray = names.reject { |name| name.end_with?(EXTENSION) }
      unless stray.empty?
        raise ValidationError, "#{dir}: #{stray.sort.join(', ')} — a split registry holds only " \
                               "<slug>#{EXTENSION} files (and _-prefixed comment-only headers)"
      end
      names
    end

    def load_directory(dir, wrapper:)
      header_files(dir).each { |file| check_header!(file) }
      merged = {}
      owners = {}
      slug_files(dir).each do |slug, file|
        key, value = slug_entry!(file, slug, wrapper: wrapper)
        merge_slug!(merged, owners, key, file, value)
      end
      wrapper ? { wrapper => merged } : merged
    end

    def check_header!(file)
      data = YAML.safe_load_file(file)
      return if data.nil? || data == {}

      raise ValidationError, "#{file}: a #{HEADER_PREFIX}-prefixed header file must be comment-only " \
                             "documentation — move any entry into its own <slug>#{EXTENSION}"
    end

    # The one [key, value] a slug file defines, after the guards.
    def slug_entry!(file, slug, wrapper:)
      text = File.read(file, encoding: "UTF-8")
      data = YAML.safe_load(text) || {}
      raise ValidationError, "#{file}: must be a mapping, got #{data.class}" unless data.is_a?(Hash)

      indent = ""
      if wrapper
        unless data.keys == [wrapper] && data[wrapper].is_a?(Hash)
          raise ValidationError, "#{file}: must hold exactly one top-level `#{wrapper}:` mapping"
        end

        data = data[wrapper]
        indent = "  "
      end
      check_single_key!(file, slug, data, text, indent)
      data.first
    end

    def check_single_key!(file, slug, data, text, indent)
      unless data.size == 1
        raise ValidationError, "#{file}: must define exactly one slug (its filename, #{slug.inspect}), " \
                               "got #{data.keys.map(&:to_s).inspect}"
      end
      key = data.keys.first
      unless key.to_s == slug
        raise ValidationError, "#{file}: defines #{key.to_s.inspect} — the slug key must match its " \
                               "filename (#{slug.inspect})"
      end
      lines = text.scan(/^#{indent}#{Regexp.escape(slug)}:(?:\s|$)/).size
      return if lines == 1

      raise ValidationError, "#{file}: slug #{slug.inspect} defined #{lines} times (YAML would keep only " \
                             "the last silently) — one block-style key line per file"
    end

    def merge_slug!(merged, owners, key, file, value)
      slug = key.to_s
      if owners.key?(slug)
        raise ValidationError, "slug #{slug.inspect} is defined by both #{File.basename(owners[slug])} and " \
                               "#{File.basename(file)}"
      end

      owners[slug] = file
      merged[key] = value
    end
    private_class_method :load_directory, :check_header!, :slug_entry!, :check_single_key!, :merge_slug!,
                         :entries
  end
end
