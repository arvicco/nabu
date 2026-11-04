# frozen_string_literal: true

require "json"

# The timeline-registration guard: a source whose parsed documents carry
# date-shaped metadata must REACH the public dating axis. Nothing else fails
# when an adapter mints a date hash and MetadataDates::SHAPES never learns
# the source — the shelf just sits dark on --from/--to/--century. emmo
# shipped exactly so (100 dated manuscripts invisible for a whole release,
# found by accident); the live health census (Invariants#timeline_lane_drift)
# only sees it after a sync, against the catalog. This guard promotes that
# same reading (Invariants::DATE_BOUNDS_MARKER) into the suite: the
# conformance suite applies #violation to every adapter's parsed fixtures,
# so the drift fails at the adapter's own test, before it ships.
#
# A flagged source has exactly two legal fixes: a SHAPES row
# (lib/nabu/store/timeline_builder/metadata_dates.rb), or an OPT_OUTS row
# here naming the lane that does project its dates, with the reason.
module TimelineRegistrationGuard
  SHAPES = Nabu::Store::TimelineBuilder::MetadataDates::SHAPES

  # The date-shaped key families — each is the input of a SHAPES reader
  # (the shape list at the top of metadata_dates.rb). "not_before" is the
  # health reading verbatim (anywhere in the serialized metadata — the
  # structured hash, bounds_keys, era_band, the NDL catalog record); the
  # rest are top-level keys. Label-banded shapes keyed on non-date words
  # (script_band's "script", work_era's "book"/"work", archive_axes'
  # "archive", place_only) are deliberately absent: their keys are not
  # date-shaped and ride many sources for other lanes.
  FAMILIES = {
    "date" => %w[date], # structured / year_range / ce_year_text / century_prose / period_label objects
    "date_not_before/date_not_after" => %w[date_not_before date_not_after], # iso_keys
    "datefrom/dateto" => %w[datefrom dateto], # compact_date_keys
    "creation_date" => %w[creation_date], # signed_year_key
    "start_date/end_date" => %w[start_date end_date], # signed_bounds_keys
    "birth_century/death_century" => %w[birth_century death_century], # author_century_band
    "date_iso" => %w[date_iso], # iso_prefix_key
    "orig_date" => %w[orig_date], # when_key
    "era_band" => %w[era_band], # era_band_key / header_year_or_era_band
    "year" => %w[year], # year_key / header_year_or_era_band
    "period" => %w[period], # period_label / century_prose
    "dynasty" => %w[dynasty], # dynasty_band
    "dcs_time_slot" => %w[dcs_time_slot], # time_slot_band
    "source_date" => %w[source_date], # edition_year_text
    "printed_date" => %w[printed_date] # printed_year_text
  }.freeze

  # Sources whose date-shaped metadata is consumed by ANOTHER timeline lane
  # — a canonical-walking extractor under TimelineBuilder — so a SHAPES row
  # would double their rows. Every row names the lane (a TimelineBuilder
  # constant or method; the ledger test fails when it disappears) and why.
  OPT_OUTS = {
    # AesDates reads the corpus's six coarse period values from canonical
    # and bands them; metadata "date" is the same value riding verbatim.
    "aes" => { lane: "AesDates", reason: "AesDates bands the sentence date values from canonical" },
    # CdliDates parses the catalog's own period strings ("Ur III (ca.
    # 2100-2000 BC)") — the honesty rule; metadata "period" is that string.
    "cdli" => { lane: "CdliDates", reason: "CdliDates parses the catalog period strings from canonical" },
    # CorphDates runs the honest parse ladder over TEXT.Date prose; the
    # metadata "date" is the same prose, verbatim.
    "corph" => { lane: "CorphDates", reason: "CorphDates parses the ChronHib TEXT.Date prose from canonical" },
    # DamaskiniDates reads the TSV header witness dates, joined by urn.
    "damaskini" => { lane: "DamaskiniDates", reason: "DamaskiniDates reads the TSV header witness dates" },
    # goo300k/imp: the CE year rides the urn suffix (urn = f(canonical));
    # TimelineBuilder.build_year_from_urn mints the rows.
    "goo300k" => { lane: "build_year_from_urn", reason: "the urn-suffix year lane dates every document" },
    "imp" => { lane: "build_year_from_urn", reason: "the urn-suffix year lane dates every document" },
    # IipDates / IsicilyDates / RiigDates walk the per-record EpiDoc origDate
    # attributes and findspots from canonical — the metadata date hash is
    # the adapter's copy of the same header.
    "iip" => { lane: "IipDates", reason: "IipDates walks the EpiDoc origin/date bounds from canonical" },
    "isicily" => { lane: "IsicilyDates", reason: "IsicilyDates walks the EpiDoc origDate bounds from canonical" },
    "riig" => { lane: "RiigDates", reason: "RiigDates walks the EpiDoc origDate bounds from canonical" }
  }.freeze

  # FINDINGS, not opt-outs: sources the guard caught dark that SHOULD be
  # registered — the defect this guard exists for, held visible (and the
  # suite green) until the SHAPES row lands; the ledger test then demands
  # the row's deletion. Never a home for a source that is not a defect.
  PENDING = {}.freeze

  module_function

  # The date-shaped families one document's metadata carries.
  def families(metadata)
    return [] unless metadata.is_a?(Hash) && !metadata.empty?

    found = FAMILIES.filter_map { |label, keys| label if keys.any? { |key| metadata.key?(key) } }
    found.unshift("not_before") if JSON.generate(metadata).include?(Nabu::Health::Invariants::DATE_BOUNDS_MARKER)
    found
  end

  # nil when +slug+ may carry +metadatas+ (registered, opted out, pending,
  # or undated); else the failure message naming the source, the families
  # found (with document counts) and the two legal fixes.
  def violation(slug, metadatas)
    return nil if SHAPES.key?(slug) || OPT_OUTS.key?(slug) || PENDING.key?(slug)

    tally = metadatas.flat_map { |metadata| families(metadata) }.tally
    return nil if tally.empty?

    found = tally.map { |family, count| "#{family} (#{count} doc#{'s' unless count == 1})" }.join(", ")
    "source #{slug.inspect} mints date-shaped metadata [#{found}] but is not registered in " \
      "Nabu::Store::TimelineBuilder::MetadataDates::SHAPES — its documents will sit dark on the " \
      "timeline (the emmo defect). Fix: add a SHAPES row for #{slug.inspect} naming the shape that " \
      "reads these keys, OR (when another timeline lane already projects these dates) add an " \
      "OPT_OUTS row in test/support/timeline_registration_guard.rb naming that lane and the reason."
  end
end
