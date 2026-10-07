# frozen_string_literal: true

require "digest"
require "fileutils"

# A whole-tree parse digest for zero-diff parity pins (the ReM/ReN CorA-XML
# sibling zips): every discovered document's urn, language, title, canonical
# metadata JSON and passage content hashes (Store::ContentHash — the
# loader's own idempotency encoding), in discover order. canonical_path is
# deliberately left out so a tmpdir copy of a fixture tree digests the same
# as the tree itself.
module ParseTreeDigest
  module_function

  def tree_digest(adapter, workdir)
    content_hash = Nabu::Store::ContentHash
    lines = adapter.discover(workdir).map do |ref|
      document = adapter.parse(ref)
      content_hash.digest(document.urn, document.language, document.title,
                          content_hash.canonical_json(document.metadata),
                          *document.map { |passage| content_hash.passage(passage) })
    end
    Digest::SHA256.hexdigest(lines.join("\n"))
  end

  # Copy +source+'s fixture tree into +dir+ minus the +excluded+ top-level
  # subtree (the sibling zip's materialization) — today's canonical state.
  def copy_tree_without(source, dir, excluded:)
    Dir.glob("**/*", base: source).each do |rel|
      next if rel == excluded || rel.start_with?("#{excluded}/")

      from = File.join(source, rel)
      next unless File.file?(from)

      FileUtils.mkdir_p(File.join(dir, File.dirname(rel)))
      FileUtils.cp(from, File.join(dir, rel))
    end
  end
end
