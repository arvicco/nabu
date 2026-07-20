# frozen_string_literal: true

module Nabu
  module Adapters
    # The text-fabric parser family (P30-4, parser family "text-fabric"):
    # plain-Ruby readers for the .tf feature files of an ETCBC-style
    # Text-Fabric dataset (annotation.github.io/text-fabric). Built for
    # REUSE — bhsa registers first, dss second (P30-5), peshitta and the
    # Samaritan Pentateuch later — so everything here is FORMAT, and every
    # corpus policy (which features ride tokens, how refs are minted, the
    # license) stays in the registering adapter.
    #
    # == The format (what a .tf file is)
    #
    # One file per feature. A header block of @-lines — the first names the
    # kind (@node, @edge or @config), the rest are @key=value metadata
    # (@valueType=str|int) — then ONE blank line, then data: one value per
    # line, the line's position encoding the node number (previous node + 1,
    # starting at 1). A line may instead carry an explicit anchor —
    # node<TAB>value — where the node spec can be a single node ("3897"), a
    # range ("1-426590", how otype.tf types whole blocks) or a comma list of
    # ranges; the next implicit line continues from the spec's highest node.
    # An EMPTY line in the data section is an empty value for the next node
    # (BHSA's kq_hybrid ships 424,723 of them), NOT a separator — only the
    # first blank line after the header separates; empty values advance the
    # node cursor but load as ABSENT (no consumer distinguishes "" from
    # absent, and materializing them would triple the run count). @config
    # files (otext.tf) are header-only. Values unescape \t, \n and \\ per
    # the TF spec (BHSA 2021 carries zero escapes — pinned in the fixture
    # README).
    #
    # oslots.tf is the ONE structural edge: node<TAB>slot-spec maps every
    # non-slot node to the slot (word) nodes it comprises; slot specs are
    # range lists and MAY be non-contiguous ("298646-298650,298655-298657" —
    # 2,454 BHSA clauses are discontinuous). otype.tf types every node by
    # range; the run starting at node 1 is the slot type, and its end is
    # maxSlot. Edge features WITH values (@edgeValues — BHSA's omap@*
    # version maps) are not parsed: no registrant reads them, and untested
    # support would be invented format (ParseError names the file instead).
    #
    # == Shapes
    #
    #   Feature.load(path) -> a Feature: kind (:node/:edge/:config), meta,
    #     fetch(node), each_pair, each_run. Values are Integers when the
    #     header declares @valueType=int (empty values stay absent).
    #   Dataset.new(dir)   -> lazy Feature cache over <dir>/<name>.tf plus
    #     the otype/oslots structure: type_of, type_ranges, max_slot,
    #     slot_ranges(node).
    #
    # Runs are kept as [start, end, value] triples exactly as read (a
    # trimmed fixture and the full corpus are the same shape), and fetch is
    # a binary search — nothing materializes 426,590-entry hashes unless a
    # caller iterates. Node order must ascend, as Text-Fabric itself writes
    # it; a descending anchor is damage (ParseError), never resorted.
    class TextFabric
      KINDS = { "@node" => :node, "@edge" => :edge, "@config" => :config }.freeze

      # Parse a Text-Fabric node/slot spec ("3", "1-5", "1-5,9") into an
      # ascending array of inclusive [first, last] integer pairs.
      def self.parse_ranges(spec, path: nil)
        spec.split(",").map do |part|
          first, dash, last = part.partition("-")
          [integer!(first, path: path), dash.empty? ? integer!(first, path: path) : integer!(last, path: path)]
        end
      end

      def self.integer!(text, path: nil)
        Integer(text, 10)
      rescue ArgumentError, TypeError
        raise Nabu::ParseError, "#{path || 'text-fabric'}: #{text.inspect} is not a node number"
      end

      # One .tf feature file: header meta + the data runs.
      class Feature
        attr_reader :path, :kind, :meta

        def self.load(path)
          raise Nabu::ParseError, "#{path}: no such .tf file" unless File.file?(path)

          new(path)
        end

        def initialize(path)
          @path = path
          @starts = []
          @ends = []
          @values = []
          lines = File.read(path, encoding: "UTF-8").split("\n", -1)
          lines.pop if lines.last == "" # the file-terminating newline, never a value
          read_header(lines)
          read_data(lines)
        end

        def value_type = (meta["valueType"] == "int" ? :int : :str)
        def config? = kind == :config
        def edge? = kind == :edge
        def empty? = @starts.empty?

        # The last node the feature covers (runs are ascending), nil when
        # empty — a sibling feature MODULE (ETCBC/bridging, P34-1) is sanity-
        # checked against the core dataset's slot space via this.
        def max_node = @ends.last

        # The value at +node+, or +default+ when the feature does not cover
        # it. Binary search over the ascending runs.
        def fetch(node, default = nil)
          index = run_index(node)
          index ? @values[index] : default
        end

        # Every (node, value) pair in ascending node order, ranges expanded.
        def each_pair
          return enum_for(:each_pair) unless block_given?

          @starts.each_index do |i|
            (@starts[i]..@ends[i]).each { |node| yield node, @values[i] }
          end
        end

        # The runs as read: (first, last, value) — otype consumers read the
        # ranges themselves rather than expanding a million nodes.
        def each_run
          return enum_for(:each_run) unless block_given?

          @starts.each_index { |i| yield @starts[i], @ends[i], @values[i] }
        end

        private

        def read_header(lines)
          @kind = KINDS[lines.first]
          if @kind.nil?
            raise Nabu::ParseError,
                  "#{path}: a .tf file opens with @node, @edge or @config, got #{lines.first.inspect}"
          end

          @meta = {}
          @data_from = nil
          lines.each_with_index do |line, index|
            next if index.zero?
            break (@data_from = index + 1) if line == ""
            unless line.start_with?("@")
              raise Nabu::ParseError, "#{path}: header line #{index + 1} is neither @key=value nor blank"
            end

            key, _eq, value = line.delete_prefix("@").partition("=")
            @meta[key] = value # a valueless key (@edgeValues) records as ""
          end
          return unless meta.key?("edgeValues")

          raise Nabu::ParseError,
                "#{path}: @edgeValues features are not supported (no registered text-fabric corpus reads them)"
        end

        def read_data(lines)
          data = @data_from ? lines[@data_from..] : []
          if config?
            raise Nabu::ParseError, "#{path}: a @config feature carries no data lines" unless data.all?("")

            return
          end
          @cursor = 0 # the highest node any data line has named so far
          data.each { |line| append_line(line) }
        end

        def append_line(line)
          spec, tab, payload = line.partition("\t")
          if tab.empty?
            append_run(@cursor + 1, @cursor + 1, spec) # implicit: previous node + 1, first node 1
          else
            raise Nabu::ParseError, "#{path}: #{line.inspect} has more than one tab" if payload.include?("\t")

            TextFabric.parse_ranges(spec, path: path).each { |first, last| append_run(first, last, payload) }
          end
        end

        def append_run(first, last, payload)
          if first > last || first <= @cursor
            raise Nabu::ParseError,
                  "#{path}: node run #{first}-#{last} does not ascend past #{@cursor} — " \
                  "Text-Fabric writes nodes in ascending order; anything else is damage"
          end

          @cursor = last
          value = value_for(payload)
          return if value.nil? # an empty value is an absent value, never content

          @starts << first
          @ends << last
          @values << value
        end

        def value_for(payload)
          value = unescape(payload)
          return nil if value.empty?
          return value unless value_type == :int

          TextFabric.integer!(value, path: path)
        end

        def unescape(payload)
          return payload unless payload.include?("\\")

          payload.gsub(/\\[tn\\]/, "\\t" => "\t", "\\n" => "\n", "\\\\" => "\\")
        end

        # Index of the run covering +node+, or nil.
        def run_index(node)
          low = 0
          high = @starts.length - 1
          while low <= high
            mid = (low + high) / 2
            if node < @starts[mid] then high = mid - 1
            elsif node > @ends[mid] then low = mid + 1
            else return mid
            end
          end
          nil
        end
      end

      # A directory of .tf files: lazy per-feature loading plus the
      # otype/oslots structure every Text-Fabric corpus shares.
      class Dataset
        attr_reader :dir

        def initialize(dir)
          @dir = dir
          @features = {}
        end

        def feature(name)
          @features[name] ||= Feature.load(File.join(dir, "#{name}.tf"))
        end

        def feature?(name)
          File.file?(File.join(dir, "#{name}.tf"))
        end

        # { type => [[first, last], ...] } from otype's runs.
        def type_ranges
          @type_ranges ||= feature("otype").each_run.with_object({}) do |(first, last, type), ranges|
            (ranges[type] ||= []) << [first, last]
          end
        end

        def type_of(node)
          feature("otype").fetch(node)
        end

        def type_count(type)
          type_ranges.fetch(type, []).sum { |first, last| last - first + 1 }
        end

        # The slot type is the otype run starting at node 1 (Text-Fabric's
        # own definition); its end is maxSlot.
        def max_slot
          @max_slot ||= begin
            run = feature("otype").each_run.find { |first, _last, _type| first == 1 }
            raise Nabu::ParseError, "#{dir}: otype.tf has no run starting at node 1 — no slot type" if run.nil?

            run[1]
          end
        end

        # The inclusive slot ranges of +node+: itself for a slot, its oslots
        # edge for anything else, nil when oslots does not cover it.
        def slot_ranges(node)
          return [[node, node]] if node <= max_slot

          spec = feature("oslots").fetch(node)
          spec && TextFabric.parse_ranges(spec, path: File.join(dir, "oslots.tf"))
        end
      end
    end
  end
end
