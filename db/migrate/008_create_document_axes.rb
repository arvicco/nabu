# frozen_string_literal: true

# The date/place axis (P15-2, design doc §3): a catalog-side table of
# document-level date ranges and provenance places, populated at load time by
# per-source axis extractors reading canonical (Store::AxisBuilder). NOT columns
# on documents — a document may carry zero, one, or (Part 2's chronicle
# passage-grain) several axis rows, and most of the corpus is undated (an
# ABSENCE, never a row).
#
# == The date model (fable-reviewed 2026-07-12 — see backlog P15-2)
#
# - not_before / not_after: signed integer HISTORICAL years — negative = BCE,
#   positive = CE, and there is NO year 0 (1 BCE = -1, 1 CE = +1). HGV encodes
#   `when="-0113"` as 113 BCE (verified against its own "113 v.Chr." label —
#   historical numbering, not ISO astronomical), so the integer is ingested
#   verbatim and `search --from -300 --to -30` means 300 BCE … 30 BCE with no
#   conversion. A POINT stores not_before = not_after; a RANGE stores honest
#   bounds ("VI–VII low" → 501, 700), never a fake midpoint. Either bound may be
#   NULL for an OPEN-ENDED interval (HGV notBefore-only / notAfter-only) —
#   read as −∞ / +∞ by the NULL-aware overlap filter. SQLite integer sort is
#   chronological across the era boundary (-300 < -30 < 14 < 501).
# - precision: HGV's precision attribute verbatim when present ("low"/…), else
#   "exact" for a `when`-point or "range" for a notBefore/notAfter pair.
# - date_raw: the upstream origDate string ("26. Aug. 113 v.Chr.") — honesty
#   survives normalization (conventions §3: there is no "original", only what
#   the source said).
# - place_name / place_ref: origPlace text + the provenance placeName ref URL(s)
#   (Trismegistos/Pleiades), both verbatim strings — no gazetteer (the §1.4
#   stance holds). goo300k/IMP carry no place (NULL).
# - axis_source: which extractor minted the row (hgv / goo300k / imp).
# - passage_seq_from / passage_seq_to: NULL for document-grain rows; Part 2's
#   chronicle-annal extractor fills them (dating at passage-range grain within
#   one document). Shipped now so Part 2 needs no second migration.
Sequel.migration do
  change do
    create_table(:document_axes) do
      primary_key :id
      foreign_key :document_id, :documents, null: false
      Integer :not_before
      Integer :not_after
      String :precision
      String :date_raw
      String :place_name
      String :place_ref
      String :axis_source, null: false
      Integer :passage_seq_from
      Integer :passage_seq_to

      index :document_id
      index %i[not_before not_after]
      index :place_name
    end
  end
end
