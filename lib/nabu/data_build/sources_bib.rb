# frozen_string_literal: true

require_relative "builder"

module Nabu
  module DataBuild
    # sources.bib — the dataset's citation file, rendered from the builder's
    # structured Citation values (never free-text pasted BibTeX). Keys obey
    # the CLDF identifier regex (Citation enforces it) so CSV Source columns
    # can cite them ";"-separated, the CLDF way.
    class SourcesBib
      FILENAME = "sources.bib"

      # Write sources.bib into +dir+; returns the file path. An empty
      # citation list still ships the file (with only the header comment) so
      # the dataset layout is uniform.
      def self.write(dir:, citations:, slug:)
        path = File.join(dir, FILENAME)
        File.write(path, render(citations: citations, slug: slug))
        path
      end

      def self.render(citations:, slug:)
        header = "% sources.bib for #{slug} — cite these keys from CSV Source columns (\";\"-separated)\n"
        ([header] + citations.map { |citation| entry(citation) }).join("\n")
      end

      def self.entry(citation)
        fields = citation.fields.map { |name, value| "  #{name} = {#{value}}" }.join(",\n")
        "@#{citation.type}{#{citation.key},\n#{fields}\n}\n"
      end

      # The manifest resource entry: non-tabular, so no schema — format and
      # mediatype say what the file is.
      def self.resource
        Resource.new(name: "sources", path: FILENAME, format: "bibtex", mediatype: "text/x-bibtex")
      end
    end
  end
end
