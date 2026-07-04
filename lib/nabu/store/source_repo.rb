# frozen_string_literal: true

module Nabu
  module Store
    # One upstream git repo of a multi-repo source (UD: one row per treebank),
    # carrying its own last_sync_sha and license baseline — the per-repo
    # analogue of the sources columns (P6-3). Written by SyncRunner's
    # update_source_state from the FetchReport's per-repo shas; read (and its
    # license baseline recorded) by Health::RemoteProbe. No business logic here.
    class SourceRepo < Sequel::Model(:source_repos)
      many_to_one :source, class: "Nabu::Store::Source", key: :source_id
    end
  end
end
