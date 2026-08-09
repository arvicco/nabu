# frozen_string_literal: true

require "yaml"

module Nabu
  # Place dossiers (P64-4, ruling Dp-e — the program-tail packet): the
  # owner's AUTHORED essays about places, as canonical-memory files under
  # canonical/local-place/<key>.md — front-matter (key + the namespaced refs
  # the essay is about) and a Markdown body. The place desk renders the
  # dossier section when a card's ids intersect a dossier's refs.
  #
  # v1 is deliberately lean: files are read at desk time (the pleiades-v1
  # read posture — no catalog table, no migration, no scaffolder: dossiers
  # are authored, never seeded; the Q3 lesson). The LanguageShelf-style
  # derive/accretion machinery arrives if and when the shelf grows past
  # hand-reading scale.
  module PlaceDossiers
    DIRNAME = "local-place"

    Dossier = Data.define(:key, :title, :refs, :body)

    module_function

    # Every dossier under canonical/local-place, file order. Absent dir =
    # no dossiers, honestly. A malformed file raises loudly (owner-authored
    # files deserve loud feedback, not silent skips).
    def all(canonical_dir)
      dir = File.join(canonical_dir, DIRNAME)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, "*.md")).map { |path| parse(path) }
    end

    # Dossiers whose refs intersect +ids+ ([[namespace, id], …] pairs from
    # the card being rendered).
    def for_ids(canonical_dir, ids)
      wanted = ids.map { |ns, id| "#{ns}:#{id}" }
      all(canonical_dir).select { |d| d.refs.intersect?(wanted) }
    end

    def parse(path)
      raw = File.read(path, encoding: "UTF-8")
      m = raw.match(/\A---\n(.*?)\n---\n(.*)\z/m) or
        raise Nabu::Error, "#{path}: a place dossier needs front-matter (---\\n…\\n---) + body"
      front = YAML.safe_load(m[1])
      refs = Array(front["refs"]).map(&:to_s)
      raise Nabu::Error, "#{path}: front-matter needs refs: [namespace:id, …]" if refs.empty?

      Dossier.new(key: front.fetch("key", File.basename(path, ".md")),
                  title: front.fetch("title", File.basename(path, ".md")),
                  refs: refs, body: m[2].strip)
    end
  end
end
