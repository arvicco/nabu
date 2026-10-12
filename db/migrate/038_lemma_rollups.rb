# frozen_string_literal: true

# P121-2: the lemma attestation instrument — three precompiled rollups
# written by Store::LemmaRollup so the `lemma` and `language --curve /
# --mixing` desks answer from a few indexed rows, never a live scan of
# passages or passage_lemmas (the desk-commands law).
#
# - lemma_rollup: one row per (lemma, language, century, basis, grade,
#   source) — attestation counts behind `nabu lemma FORM`. lemma is the
#   FOLDED key (passage_lemmas.lemma_folded, the fold-both-sides lookup
#   contract); century is the signed century index of the document's
#   date-envelope midpoint (NULL = undated); basis the envelope's date
#   class (NULL = undated); grade "gold" | "silver" (the passage_lemmas
#   tier). occurrences counts passage attestations (the passage_lemmas
#   grain: one per distinct lemma per passage), documents the distinct
#   documents.
# - language_curve: documents + passages per (language, century, basis,
#   source) — the `language CODE --curve` profile.
# - language_mix: one row per live document — its sorted passage-language
#   inventory and adjacent-passage switch count — the `language --mixing`
#   multilingualism census.
#
# Derived: drop-and-reproject wholesale at rebuild / builders:refresh,
# per source after a sync. The unique keys are the natural grain; SQLite
# treats NULLs as distinct in a unique index, so the builder's GROUP BY is
# what actually guarantees one undated row per remaining key.
Sequel.migration do
  change do
    create_table(:lemma_rollup) do
      String :lemma, null: false
      String :language, null: false
      Integer :century
      String :basis
      String :grade, null: false
      foreign_key :source_id, :sources, null: false
      Integer :occurrences, null: false
      Integer :documents, null: false
      index %i[lemma language century basis grade source_id], unique: true,
                                                              name: :lemma_rollup_key
      index %i[language grade]
    end

    create_table(:language_curve) do
      String :language, null: false
      Integer :century
      String :basis
      foreign_key :source_id, :sources, null: false
      Integer :documents, null: false
      Integer :passages, null: false
      index %i[language century basis source_id], unique: true, name: :language_curve_key
    end

    create_table(:language_mix) do
      foreign_key :document_id, :documents, null: false
      foreign_key :source_id, :sources, null: false
      String :urn, null: false
      String :languages, null: false
      Integer :language_count, null: false
      Integer :switches, null: false
      index :document_id, unique: true
      index :source_id
      index %i[language_count languages]
    end
  end
end
