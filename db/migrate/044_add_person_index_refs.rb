# frozen_string_literal: true

# The external-authority lane on the person index: a person's links into
# other prosopographies, as the authority file itself spells them —
# space-separated verbatim URLs (the place_ref doctrine: upstream bytes
# kept, joins by normalization). The Elephantine authority links 2,687 of
# its persons to Trismegistos People records and 2,712 of its names to TM
# name records; CBDB carries no such link in the slice read (NULL). No
# backfill: the person index is derived wholesale per authority.
Sequel.migration do
  change do
    alter_table(:person_index) do
      add_column :refs, String
    end
  end
end
