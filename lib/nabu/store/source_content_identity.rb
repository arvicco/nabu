# frozen_string_literal: true

require "digest"

module Nabu
  module Store
    # One source's LIVE derived content, named (Nabu::LinkStamps' member
    # identity): a sha256 over the source's license posture, its live
    # documents' (urn, content_sha256, license_override) in urn order, and
    # its dictionaries' live entries' (entry_id, content_sha256).
    #
    # Why content and not the derivation stamp: a links producer reads the
    # catalog's CONTENT, so its edges are a function of that content — a
    # content-neutral edit to the loader (or anything else in the shared
    # derivation core) moves every source's derivation fingerprint while
    # leaving every row byte-identical, and must not re-mine hours of
    # edges. The document sha already covers its passages (urn, language,
    # text, text_normalized, annotations, sequence — Store::ContentHash),
    # so one row per document names the whole visible passage set. Withdrawn
    # rows are excluded on purpose: they are invisible to every producer,
    # and an incremental's tombstone must read the same as a full rebuild's
    # absence. Cost on the live catalog (2.4M documents, 3.1M entries):
    # one indexed pass, tens of seconds — paid once per links stage.
    module SourceContentIdentity
      SEPARATOR = "\x1f"

      module_function

      # { slug => identity } for +slugs+ (sorted); a slug with no sources
      # row reads "absent" — honest, and distinct from any real digest.
      def for_slugs(db, slugs)
        rows = db[:sources].where(slug: slugs).as_hash(:slug, %i[id license_class])
        slugs.sort.to_h do |slug|
          row = rows[slug]
          [slug, row ? identity(db, *row) : "absent"]
        end
      end

      def identity(db, source_id, license_class)
        digest = Digest::SHA256.new
        digest << "license#{SEPARATOR}#{license_class}\n"
        db[:documents].where(source_id: source_id, withdrawn: false).order(:urn)
                      .select(:urn, :content_sha256, :license_override).each do |row|
          digest << ["d", row[:urn], row[:content_sha256], row[:license_override].to_s].join(SEPARATOR) << "\n"
        end
        db[:dictionaries].where(source_id: source_id).order(:slug).all.each do |dictionary|
          digest << ["D", dictionary[:slug], dictionary[:language], dictionary[:title]].join(SEPARATOR) << "\n"
          db[:dictionary_entries].where(dictionary_id: dictionary[:id], withdrawn: false).order(:entry_id)
                                 .select(:entry_id, :content_sha256).each do |row|
            digest << ["e", row[:entry_id], row[:content_sha256]].join(SEPARATOR) << "\n"
          end
        end
        digest.hexdigest
      end
    end
  end
end
