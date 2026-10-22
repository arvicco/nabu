# frozen_string_literal: true

# The OSL sign concordances: the concordance assets riding in the held
# Oracc Sign List repo's 00etc (canonical/osl/00etc — CC0 with the repo,
# never parsed before) joined onto the OSL sign ids (@oid) the sign card
# already keys: the Wikidata list concordances (Labat, AKS, ATU1 and the
# other printed lists), the AKS oid table, MZL↔KWU, PGSL, the eBL sign
# names, Wikidata item ids, and the Attinger / short-form / ŋ-less value
# maps. One row per (oid, scheme, key, value) fact:
#
# - scheme: the concordance (a list name like "Labat", or "MZL-KWU",
#   "PGSL", "eBL", "Wikidata", "attinger", "csf", "eng")
# - key:    the left side of a pair (the MZL number of an MZL↔KWU row,
#           the OSL value a value map maps FROM); NULL for plain numbers
# - value:  the number / name / mapped spelling (NULL only on an MZL↔KWU
#           row whose KWU side upstream leaves unnumbered)
# - asset:  the 00etc file the fact came from (first asset wins a
#           duplicate fact)
# - via:    the join lane that reached the sign (qid-oid, oid, codepoint,
#           uname, name, aka, form, value)
#
# Written by Store::SignConcordances (drop-and-reproject, a pure function
# of canonical/osl — the derivability law); read by the cuneiform sign
# card, one indexed lookup per card (the desk-commands law: cards touch
# only precompiled data).
Sequel.migration do
  change do
    create_table(:sign_concordances) do
      String :oid, null: false
      String :scheme, null: false
      String :key
      String :value
      String :asset, null: false
      String :via, null: false
      index :oid
    end
  end
end
