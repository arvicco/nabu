# frozen_string_literal: true

# The reference oracle for Nabu::NameMatcher: the first-character bucket
# scan PlaceMine shipped with until the Aho-Corasick matcher replaced it,
# kept VERBATIM (bucket build + scan) so the equivalence tests compare the
# new matcher against the exact old behaviour — the same distinct names,
# in the same order.
module LegacyNameScan
  module_function

  def buckets(names)
    names.group_by { |name| name[0] }
         .transform_values { |list| list.sort_by { |n| -n.length } }
  end

  def scan(text, buckets)
    hits = nil
    i = 0
    len = text.length
    while i < len
      bucket = buckets[text[i]]
      bucket&.each do |name|
        next unless text[i, name.length] == name

        (hits ||= {})[name] = true
      end
      i += 1
    end
    hits ? hits.keys : []
  end
end
