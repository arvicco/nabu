# frozen_string_literal: true

require_relative "perseus"

module Nabu
  module Adapters
    # The PerseusLatin adapter (architecture §3, packet P7-3): PerseusDL's
    # canonical-latinLit repo is the byte-for-byte structural twin of
    # canonical-greekLit — data/<tg>/<work>/<tg>.<work>.<edition>.xml, dual
    # __cts__.xml, CTS refsDecl editions — differing only in the CTS namespace
    # baked into every urn (latinLit vs greekLit) and the original-language slug
    # (lat vs grc). Perseus was written to be parameterized by exactly that
    # namespace (see its header), so this is the documented one-line sibling:
    # NAMESPACE flips to "latinLit" and everything else — discover/parse/fetch,
    # the __cts__.xml title resolution, the highest-version selection — is
    # inherited unchanged.
    #
    # The manifest ("perseus-latin"), the language mapping (latinLit → lat) and
    # the edition-slug rule (perseus-lat<n>, derived from LANGUAGES[NAMESPACE])
    # all already live in Perseus keyed by namespace, so setting NAMESPACE is the
    # whole delta. `self::NAMESPACE` drives the class-level manifest and the
    # initializer's default, so the registry path (no-arg `.new` +
    # class-level `.manifest`) resolves the latinLit manifest with no override.
    class PerseusLatin < Perseus
      # The CTS namespace this concrete class serves — the one and only shift
      # from the greekLit parent.
      NAMESPACE = "latinLit"
    end
  end
end
