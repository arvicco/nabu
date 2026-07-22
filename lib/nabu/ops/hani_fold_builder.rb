# frozen_string_literal: true

module Nabu
  module Ops
    # P37-2: generator for lib/nabu/hani.rb — the Han trad↔simp↔z-variant
    # fold table, derived from the HELD Unihan Variants data (canonical/
    # unihan/Unihan_Variants.txt). Dev-time ops code (fingerprint-excluded):
    # the GENERATED artifact is what shapes derivation, and it rides the
    # shared-core digest like deva.rb/cyrl.rb, so a regeneration dirties
    # every source (over-rebuild-safe, P36-1).
    #
    # == Field discipline (the owner-agreed line)
    #
    # ONLY kTraditionalVariant / kSimplifiedVariant / kZVariant are read.
    # kSemanticVariant and kSpecializedSemanticVariant name different WORDS
    # that mean the same thing (㐀 "hillock" vs 丘) — folding them is a lie;
    # kSpoofingVariant is a security table, not orthography. The refusal is
    # structural: the fields never enter the graph.
    #
    # == The resolution rule (deterministic, conservative)
    #
    # Canonical form = the TRADITIONAL codepoint — what kanripo/cbeta store.
    #
    # 1. z-clusters first: union-find over kZVariant edges (undirected).
    #    Unihan's z-edge asserts "same abstract character, different glyph".
    # 2. A char's kTraditionalVariant targets (minus itself):
    #    - exactly one target                   → direct fold (亚→亞)
    #    - several targets, ALL one z-cluster   → fold to that cluster's
    #      canonical (说→{說,説}→說)
    #    - several targets across clusters      → REFUSED, censused (发→發/髮
    #      is a genuine merger of two words; picking one is a guess)
    #    - the char LISTS ITSELF as traditional → REFUSED, censused (体/台/了
    #      are traditional words in their own right; folding 了→瞭 would
    #      merge two real words) — UNLESS mutual kZVariant edges place the
    #      char and its other target(s) in one cluster (吴 self-lists but
    #      吳/吴/呉 are declared one abstract character): the z-warrant wins.
    # 3. Reverse evidence (kSimplifiedVariant, read backwards): a char named
    #    as some traditional char's simplification folds to its declarer when
    #    exactly one cluster declares it (𱃗→颱) — censused reverse_only. If
    #    reverse evidence points OUTSIDE the cluster of a direct fold, the
    #    kTraditional/kSimplified sides disagree: the fold is DROPPED and the
    #    conflict censused (never merge across a disagreement).
    # 4. Cluster canonical: the single outside traditional target its members
    #    agree on; with no outside anchor, the lowest codepoint member
    #    (說 U+8AAA < 説 U+8AAC — arbitrary but stable, and invisible: the
    #    skeleton is an index form, never display). Members disagreeing on
    #    outside targets → cluster NOT merged, censused.
    # 5. Chains compose to a fixed point (a→b→c ⇒ a→c); a cycle resolves
    #    every member to the cycle's lowest codepoint. No table value is
    #    itself a key — asserted at generation and pinned in tests.
    #
    # All codepoints pass through NFC at build time (CJK compatibility
    # ideographs decompose to their unified forms — the runtime fold only
    # ever sees post-NFC text, so the table must be keyed the same way).
    class HaniFoldBuilder
      TRAD = "kTraditionalVariant"
      SIMP = "kSimplifiedVariant"
      ZVAR = "kZVariant"
      SEMANTIC = %w[kSemanticVariant kSpecializedSemanticVariant].freeze

      # The census: provenance + every count/refusal the conventions §9 entry
      # and the generated header report.
      Census = Struct.new(:unihan_version, :unihan_date, :pairs,
                          :direct, :cluster_resolved, :reverse_only, :z_members,
                          :self_ambiguous, :multi_trad, :multi_reverse,
                          :trad_simp_conflicts, :z_conflicts, :cycles,
                          :semantic_lines_excluded, :nfc_remapped,
                          keyword_init: true)

      attr_reader :census

      def initialize(variants_path:, generated_on: Time.now.strftime("%Y-%m-%d"))
        @variants_path = variants_path
        @generated_on = generated_on
        @trad = Hash.new { |h, k| h[k] = [] }
        @simp = Hash.new { |h, k| h[k] = [] }
        @z = Hash.new { |h, k| h[k] = [] }
        @census = Census.new(direct: 0, cluster_resolved: 0, z_members: 0, cycles: 0,
                             semantic_lines_excluded: 0, nfc_remapped: 0,
                             reverse_only: [], self_ambiguous: [], multi_trad: [],
                             multi_reverse: [], trad_simp_conflicts: [], z_conflicts: [])
        parse
        resolve
      end

      # The resolved fold map: { variant char => canonical traditional char },
      # every value a fixed point, sorted by key codepoint.
      attr_reader :table

      # The lib/nabu/hani.rb source text.
      def render
        from = @table.keys.join
        to = @table.values.join
        <<~RUBY
          # frozen_string_literal: true

          # GENERATED FILE — do not edit by hand. Regenerate with:
          #   rake fold:hani            (reads canonical/unihan/Unihan_Variants.txt)
          #
          # Nabu::Hani (P37-2): the Han trad↔simp↔z-variant search fold.
          # Derived from the HELD Unihan Variants data — kTraditionalVariant /
          # kSimplifiedVariant / kZVariant ONLY (semantic variants are
          # different words; folding them is a lie). Canonical form = the
          # traditional codepoint (what kanripo/cbeta store). Resolution rule,
          # refusal censuses and provenance: Nabu::Ops::HaniFoldBuilder and
          # conventions §9.
          #
          # Provenance:
          #   Unihan version:  #{@census.unihan_version}  (file date #{@census.unihan_date})
          #   generated on:    #{@generated_on}
          #   fold pairs:      #{@table.size}
          #   directional:     #{@census.direct} direct, #{@census.cluster_resolved} via z-cluster targets,
          #                    #{@census.reverse_only.size} reverse-only, #{@census.z_members} z-cluster members
          #   refused (conservative, censused): #{@census.self_ambiguous.size} self-listing
          #                    (own traditional words: e.g. #{@census.self_ambiguous.first(5).join(' ')}),
          #                    #{@census.multi_trad.size} multi-traditional across clusters
          #                    (e.g. #{@census.multi_trad.first(5).join(' ')}),
          #                    #{@census.multi_reverse.size} multi-reverse, #{@census.trad_simp_conflicts.size} trad/simp
          #                    disagreements, #{@census.z_conflicts.size} unmergeable z-clusters, #{@census.cycles} cycles
          #   excluded:        #{@census.semantic_lines_excluded} semantic-variant lines (never read into the graph)
          #
          # Changing this table changes text_normalized for lzh/och — the
          # §9 rebuild-storm caveat applies (P36-1 dirties every source via
          # the shared-core digest; the owner schedules the re-derive).
          module Nabu
            module Hani
              UNIHAN_VERSION = "#{@census.unihan_version}"
              UNIHAN_DATE = "#{@census.unihan_date}"
              GENERATED_ON = "#{@generated_on}"

              # Variant codepoints, one char per table pair, key-sorted.
              FROM = #{heredoc_chunks(from)}

              # Canonical traditional codepoint for each FROM char (positional).
              TO = #{heredoc_chunks(to)}

              TABLE = FROM.each_char.zip(TO.each_char).to_h.freeze

              # A character class of every foldable codepoint, compiled ONCE.
              FOLD_RE = /[\#{Regexp.escape(FROM)}]/

              # Per-codepoint 1→1 fold (fold_with_map-safe: folding a string
              # char-by-char equals folding it whole).
              #
              # gsub(FOLD_RE, TABLE), NOT tr(FROM, TO): String#tr on a
              # multibyte from/to rebuilds a translation table from the whole
              # FROM string on every call, so a short passage paid the full
              # setup (the P39-3 cbeta hotspot). The regexp and hash are built
              # once; byte-identical to tr because TABLE is dup-free 1→1.
              def self.fold(str)
                str.gsub(FOLD_RE, TABLE)
              end
            end
          end
        RUBY
      end

      private

      # -- parsing -------------------------------------------------------------

      def parse
        File.foreach(@variants_path, encoding: Encoding::UTF_8) do |line|
          if line.start_with?("#")
            parse_header(line)
            next
          end
          next if line.strip.empty?

          code, field, value = line.chomp.split("\t", 3)
          next unless code && field && value

          @census.semantic_lines_excluded += 1 if SEMANTIC.include?(field)
          bucket = { TRAD => @trad, SIMP => @simp, ZVAR => @z }[field] or next
          bucket[nfc_char(code)].concat(targets(value))
        end
        [@trad, @simp, @z].each { |bucket| bucket.transform_values!(&:uniq) }
        @census.unihan_version ||= "unknown"
        @census.unihan_date ||= "unknown"
      end

      def parse_header(line)
        case line
        when /^# Date: (\d{4}-\d{2}-\d{2})/ then @census.unihan_date = Regexp.last_match(1)
        when /^# Unicode Version (\S+)/ then @census.unihan_version = Regexp.last_match(1)
        end
      end

      # "U+8A9E<kMeyerWempe U+310D7" → NFC chars; source tags stripped.
      def targets(value)
        value.split.filter_map do |token|
          hex = token[/\AU\+(\h{4,6})/, 1]
          nfc_char("U+#{hex}") if hex
        end
      end

      def nfc_char(code)
        hex = code[/\AU\+(\h{4,6})\z/, 1] or
          raise Nabu::Error, "hani-fold: malformed codepoint #{code.inspect}"
        raw = [hex.to_i(16)].pack("U")
        char = raw.unicode_normalize(:nfc)
        @census.nfc_remapped += 1 if char != raw
        char
      end

      # -- resolution ----------------------------------------------------------

      def resolve
        build_clusters
        edges = {}
        refused = Set.new
        directional_edges(edges, refused)
        cluster_edges(edges, refused)
        @table = fixed_point(edges)
      end

      # Union-find over kZVariant edges.
      def build_clusters
        @parent = {}
        @z.each do |char, tgts|
          tgts.each { |t| union(char, t) }
        end
      end

      def find(char)
        @parent[char] ||= char
        @parent[char] = find(@parent[char]) unless @parent[char] == char
        @parent[char]
      end

      def union(one, other)
        root_one = find(one)
        root_other = find(other)
        @parent[root_other] = root_one unless root_one == root_other
      end

      # Root only when the char actually sits in a z-cluster; otherwise self.
      def root(char)
        @parent.key?(char) ? find(char) : char
      end

      def clustered?(char)
        @parent.key?(char)
      end

      # Steps 2–3: per-char directional candidate + reverse cross-check.
      def directional_edges(edges, refused)
        reverse = reverse_candidates
        @trad.each_key do |char|
          target = trad_candidate(char, refused)
          next unless target

          if disagrees?(char, target, reverse)
            refused << char
            @census.trad_simp_conflicts << char
          else
            edges[char] = target
            target.is_a?(String) ? @census.direct += 1 : @census.cluster_resolved += 1
          end
        end
        reverse_only_edges(edges, refused, reverse)
      end

      # nil (no fold), a char, or [:cluster, root] when the fold's target is
      # a z-cluster whose canonical is chosen later.
      def trad_candidate(char, refused)
        nonself = @trad[char] - [char]
        return nil if nonself.empty?

        if @trad[char].include?(char)
          # Self-listing: its own traditional word — unless the z-warrant
          # covers char AND all its other targets (one abstract character).
          return nil if clustered?(char) && nonself.all? { |t| root(t) == root(char) }

          refused << char
          @census.self_ambiguous << char
          return nil
        end
        roots = nonself.map { |t| root(t) }.uniq
        return nonself.first if nonself.size == 1
        return [:cluster, roots.first] if roots.size == 1 && nonself.all? { |t| clustered?(t) }

        refused << char
        @census.multi_trad << char
        nil
      end

      # { simplified char => [traditional declarers] } from kSimplifiedVariant.
      def reverse_candidates
        reverse = Hash.new { |h, k| h[k] = [] }
        @simp.each do |trad_char, tgts|
          (tgts - [trad_char]).each { |v| reverse[v] << trad_char }
        end
        reverse
      end

      # Reverse evidence pointing outside the direct fold's target cluster =
      # the kTraditional/kSimplified sides disagree.
      def disagrees?(char, target, reverse)
        declarers = reverse[char]
        return false if declarers.empty?

        target_root = target.is_a?(String) ? root(target) : target.last
        declarers.any? { |u| root(u) != target_root }
      end

      def reverse_only_edges(edges, refused, reverse)
        reverse.each do |char, declarers|
          next if edges.key?(char) || refused.include?(char) || @trad.key?(char)
          next if clustered?(char) && declarers.all? { |u| root(u) == root(char) } # intra-cluster: step 4's job

          roots = declarers.map { |u| root(u) }.uniq
          if roots.size == 1
            edges[char] = declarers.size == 1 ? declarers.first : [:cluster, roots.first]
            @census.reverse_only << char
          else
            refused << char
            @census.multi_reverse << char
          end
        end
      end

      # Step 4: pick each cluster's canonical and fold its members.
      def cluster_edges(edges, refused)
        clusters = @parent.keys.group_by { |char| find(char) }
        canonicals = {}
        clusters.each do |cluster_root, members|
          canonical = cluster_canonical(cluster_root, members, edges, refused)
          next unless canonical

          canonicals[cluster_root] = canonical
          (members - [canonical] - refused.to_a).each do |m|
            next if edges.key?(m) # a member with its own outside fold keeps it

            edges[m] = canonical
            @census.z_members += 1
          end
        end
        # Pending [:cluster, root] targets resolve to that cluster's canonical.
        edges.keys.each do |k|
          next unless edges[k].is_a?(Array)

          canonical = canonicals[edges[k].last]
          canonical ? edges[k] = canonical : edges.delete(k) # unresolvable cluster → conservative drop
        end
      end

      # The single outside traditional target members agree on; else the
      # lowest codepoint member. Disagreement → cluster not merged (nil).
      def cluster_canonical(cluster_root, members, edges, refused)
        outside = members.filter_map do |m|
          t = edges[m]
          target_root = t.is_a?(Array) ? t.last : (t && root(t))
          target_root if target_root && target_root != cluster_root
        end.uniq
        if outside.size > 1
          @census.z_conflicts << members.sort.join
          return nil
        end
        return resolve_outside(outside.first, members) if outside.size == 1

        (members - refused.to_a).min_by(&:ord) || members.min_by(&:ord)
      end

      # The cluster's canonical when its members fold to an OUTSIDE target:
      # the target char itself (a chain the fixed-point stage resolves onward
      # when that char has its own fold).
      def resolve_outside(target_root, _members)
        target_root
      end

      # A `FROM = <<~CHARS…` heredoc snippet: the table string chunked into
      # 64-char lines (readable diffs, rubocop-clean line length).
      def heredoc_chunks(str)
        lines = str.scan(/.{1,64}/m).map { |chunk| "      #{chunk}" }
        ["<<~CHARS.delete(\"\\n\").freeze", *lines, "    CHARS"].join("\n")
      end

      # Step 5: compose edges to fixed points; cycles → lowest member.
      def fixed_point(edges)
        resolved = {}
        edges.each_key { |char| resolve_char(char, edges, resolved) }
        resolved.reject { |k, v| k == v }.sort_by { |k, _| k.ord }.to_h
      end

      def resolve_char(char, edges, resolved, trail = [])
        return resolved[char] if resolved.key?(char)
        return char unless edges.key?(char)

        if trail.include?(char) # cycle: every member → lowest codepoint
          cycle = trail[trail.index(char)..]
          low = cycle.min_by(&:ord)
          cycle.each { |m| resolved[m] = low }
          resolved[low] = low
          @census.cycles += 1
          return low
        end
        resolved[char] = resolve_char(edges[char], edges, resolved, trail + [char])
      end
    end
  end
end
