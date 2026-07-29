# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module DataBuild
    # One publishable language datum — a languages.csv row (CLDF: ID, Name,
    # Glottocode, ISO639P3code; ID is Nabu's language code). Name/glottocode/
    # ISO are STATIC declarations in the registry, verified against the
    # owner's Glottolog cone (canonical/cldf-spine) when minted — a build
    # must not depend on which reference sources happen to be synced, so
    # there is deliberately no runtime CldfSpine lookup here.
    Language = Data.define(:id, :name, :glottocode, :iso639p3)

    # The dataset slug shape: "<lang>/<feature>", lower-case, hyphen-joined
    # segments ("san/form-lemma"). The leading segment is the language code.
    SLUG_PATTERN = %r{\A[a-z0-9]+(?:-[a-z0-9]+)*/[a-z0-9]+(?:-[a-z0-9]+)*\z}

    STATUSES = %i[available planned].freeze

    # The allowed dataset licenses (owner ruling D51-a, 2026-07-29): the repo
    # default is CC BY 4.0; a dataset derived from share-alike inputs
    # publishes as CC BY-SA 4.0, and its manifest is authoritative over the
    # repo default. This closed set is the whole legal space — NC/ND can
    # NEVER join it: every dataset here is itself a derivative work built to
    # be reused, so non-commercial or no-derivatives inputs are disqualifying
    # at intake, and no NC/ND license value is ever legal on an output.
    LICENSES = %w[CC-BY-4.0 CC-BY-SA-4.0].freeze
    DEFAULT_LICENSE = "CC-BY-4.0"

    # One registered dataset feature — the full self-documentation record
    # `nabu data list` prints (owner ruling: the rail documents every
    # artifact it can produce, with rationale and recommended maintenance).
    #
    # slug            "san/form-lemma" — also the dataset directory path
    # language        a Language value (code + languages.csv statics)
    # status          :available (builder landed) | :planned (refuse to build)
    # tier            provenance tier string ("gold", "gold-derived", "silver")
    # license         the dataset's license, from LICENSES (default CC BY;
    #                 BY-SA when share-alike inputs mandate it — D51-a)
    # anchoring       how rows anchor into corpora ("none", "passage-urn")
    # inputs          source slugs consumed (empty = own authorship)
    # canonical_cones repo-relative canonical path prefixes whose git shas are
    #                 recorded in the manifest's derivation block
    # rationale       one paragraph: why this dataset exists
    # maintenance     the recommended re-derivation periodicity
    # builder         the builder class (nil while planned) — see builder.rb
    #
    # Valid by construction: a Feature that cannot honestly describe itself
    # (available with no builder, planned with one, slug/language mismatch)
    # refuses with Nabu::ValidationError.
    Feature = Data.define(:slug, :language, :title, :status, :tier, :license, :anchoring,
                          :inputs, :canonical_cones, :rationale, :maintenance, :builder) do
      def initialize(slug:, language:, title:, status:, tier:, anchoring:,
                     inputs:, canonical_cones:, rationale:, maintenance:,
                     license: DEFAULT_LICENSE, builder: nil)
        unless slug.to_s.match?(SLUG_PATTERN)
          raise Nabu::ValidationError, "feature slug #{slug.inspect} must be <lang>/<feature> " \
                                       "(lower-case, hyphen-joined segments)"
        end
        unless slug.start_with?("#{language.id}/")
          raise Nabu::ValidationError, "feature slug #{slug.inspect} must lead with its language " \
                                       "code #{language.id.inspect}"
        end
        raise Nabu::ValidationError, "feature status must be one of #{STATUSES.inspect}, got #{status.inspect}" unless
          STATUSES.include?(status)
        unless LICENSES.include?(license)
          raise Nabu::ValidationError, "feature #{slug}: license #{license.inspect} is not in the allowed " \
                                       "set #{LICENSES.inspect} (owner ruling D51-a; NC/ND inputs are " \
                                       "disqualifying, so no NC/ND value is ever legal)"
        end

        { title: title, tier: tier, anchoring: anchoring, rationale: rationale, maintenance: maintenance }
          .each do |field, value|
          raise Nabu::ValidationError, "feature #{slug}: #{field} must be a non-empty string" if
            value.to_s.strip.empty?
        end
        if status == :available && builder.nil?
          raise Nabu::ValidationError, "feature #{slug}: :available requires a builder class"
        end
        if status == :planned && !builder.nil?
          raise Nabu::ValidationError, "feature #{slug}: :planned must not carry a builder " \
                                       "(land the builder and flip the status together)"
        end

        super
      end

      def planned? = status == :planned
      def available? = status == :available
      def language_code = language.id

      # The Frictionless Data Package name (lower-case alphanumerics plus
      # ".", "-", "_" — a slash is illegal there).
      def package_name = slug.tr("/", "-")
    end
  end
end
