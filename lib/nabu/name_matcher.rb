# frozen_string_literal: true

module Nabu
  # A multi-name exact-substring matcher (Aho-Corasick) — the place mine's
  # scan: one left-to-right walk per text, whatever the size of the name
  # set, instead of probing a first-character bucket of candidate names at
  # every position.
  #
  # Contract (pinned against the replaced bucket scan by
  # test/name_matcher_test.rb): #scan returns the DISTINCT names occurring
  # in the text — overlaps allowed, each reported once — ordered by the
  # start of their first occurrence, the longer name first when two start
  # at the same character. That is exactly the order the bucket scan
  # produced, so every consumer of the hit list (edge insertion order,
  # which name's detail survives a shared place) is unchanged.
  #
  # Characters are matched as Ruby characters (codepoints), so names in
  # the supplementary planes behave like any other.
  class NameMatcher
    def initialize(names)
      @goto = [{}]
      @fail = [0]
      @out = [nil]
      names.each { |name| add(name) }
      link_failures
    end

    # The distinct names attested in +text+, in first-occurrence order
    # (see the class contract).
    def scan(text)
      goto = @goto
      fail = @fail
      out = @out
      state = 0
      found = nil
      index = 0
      text.each_char do |char|
        while (nxt = goto[state][char]).nil? && state != 0
          state = fail[state]
        end
        state = nxt || 0
        if (hits = out[state])
          found ||= {}
          hits.each { |name, length| found[name] ||= index - length + 1 }
        end
        index += 1
      end
      return [] unless found
      return found.keys if found.size == 1

      found.sort_by { |name, start| [start, -name.length] }.map!(&:first)
    end

    private

    def add(name)
      state = 0
      name.each_char do |char|
        nxt = @goto[state][char]
        unless nxt
          nxt = @goto.size
          @goto << {}
          @fail << 0
          @out << nil
          @goto[state][char] = nxt
        end
        state = nxt
      end
      @out[state] = [[name, name.length]] unless @out[state]
    end

    # Breadth-first failure links; each state's outputs absorb its failure
    # state's (shallower, so already complete), so a state lists every name
    # ending there.
    def link_failures
      queue = @goto[0].values
      until queue.empty?
        parent = queue.shift
        @goto[parent].each do |char, child|
          queue << child
          target = @fail[parent]
          target = @fail[target] while target != 0 && !@goto[target].key?(char)
          link = @goto[target][char]
          link = 0 if link.nil? || link == child
          @fail[child] = link
          inherited = @out[link]
          @out[child] = (@out[child] || []) + inherited if inherited
        end
      end
    end
  end
end
