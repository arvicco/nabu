# frozen_string_literal: true

require "nokogiri"
require_relative "source_read"
require_relative "streaming_tei_parser"

module Nabu
  module Adapters
    # The cllg-tei parser family: one edition file of the Inria CLLG corpora
    # (Corpus Liberatum Linguae Graecae — the Freed Corpus, Sources
    # Chrétiennes; gitlab.inria.fr/almanach/cllg). TEI P5, TEI namespace,
    # but citation is declared through <refsDecl>/<citeStructure> trees —
    # the DTS/Dapytains mechanism — and never a CTS cRefPattern, so the
    # EpiDoc family's three strategies (all keyed off cRefPattern or its
    # absence) cannot read it. A sibling family, not a fourth EpiDoc
    # strategy: freed bodies carry NO div[@type='edition'] wrapper and a
    # whole class of files declares no tree at all, both of which would
    # contort EpidocParser's contracts. The text-extraction rules are the
    # EpiDoc ones (notes out, breaks space, NFC at the boundary), extended
    # by the Leiden policy below.
    #
    # Streaming by contract (freed carries multi-MB editions — the
    # Republic is 1.2 MB, the largest files tens of MB): the body is read
    # with Nokogiri::XML::Reader only. The teiHeader alone — a few KB,
    # read as a byte slice up to </teiHeader> — is DOM-parsed (.header).
    #
    # == Which tree cites
    #
    # A header may carry several refsDecl trees (n="default", "physical",
    # "PG", "Bekker" …). The citing tree is refsDecl[@n='default'], else
    # the unnamed one, else the first. A file with no refsDecl/
    # citeStructure at all raises NoCitationTree (a Nabu::DocumentSkipped
    # — skip by rule, never quarantine): the freed site's "Without
    # citeStructure: 331" class (2026-10-06 build — those 331 files carry
    # NO encodingDesc at all; a grep for "citeStructure" hits only their
    # publicationStmt prose). A declared tree that opens no citable unit
    # in the body (its first level matches nothing, or matches only nodes
    # without the @n it cites by) raises ZeroMatchTree, the same
    # skip-by-rule verdict under its own reason (SC: 2 files at census).
    #
    # == The citeStructure subset (CiteXPath)
    #
    # Each level is a chain link (the census found no branching tree in
    # either corpus): @match an XPath, @use "@n" or "position()", @delim
    # joining it to its parent's ref (default "."). The match grammar is
    # the subset both corpora use — census over every default tree,
    # 2026-11-12: absolute /TEI/text/body/… paths for the first level;
    # relative "l", "./div[…]", ".//lb" below it; child "/" and descendant
    # "//" axes; name tests and "*"; predicates [@a='v'], [@a], not(…),
    # "or", "and", self::name. Anything else (position predicates,
    # functions, other axes) raises a ParseError naming the expression —
    # quarantine, loud, never a guessed reading.
    #
    # A level's nodes are of two kinds:
    #
    # - ELEMENT units (div, l, p, lg, sp, item, list, …): the unit is the
    #   element's subtree.
    # - MILESTONE units (milestone, pb, cb, lb — empty markers): the unit
    #   runs from the marker to the next marker of the same level within
    #   the same parent unit, or to the parent's end. Text crossing <p>
    #   boundaries belongs to the running unit (Plato by Burnet sections,
    #   chronicles by Boor pages). A milestone unit's children evaluate
    #   their relative path inside its span (".//lb" under a pb). An
    #   element level BELOW a milestone level is not supported (absent
    #   from both corpora) and raises.
    #
    # Passages are the leaf-level units, ref = the level values joined by
    # each level's delim ("1.2", "proem.1", "327a", "25 bis a" — @n
    # verbatim, whitespace-stripped). A matched node whose @n is blank is
    # no unit (its text flows on with its parent). Same-level matches
    # nested inside an open element unit of that level are ignored
    # (outermost wins). Two more DECLARED calls:
    #
    # - A non-leaf unit that contains NO child unit is itself emitted at
    #   its partial ref (a fragment div of prose beside fragment divs of
    #   verse) — its text is cited, never lost.
    # - Text in a non-leaf unit OUTSIDE its child units (a book's <head>
    #   beside its lines, a chunk's Latin head over its items) is not
    #   cited — the EpiDoc rule for heads outside leaves.
    #
    # Duplicate refs disambiguate deterministically (":b2", the house
    # collision tolerance), never quarantine.
    #
    # == Text policy (verified against the clones, 2026-11-12)
    #
    # Mixed content concatenates; whitespace collapses; NFC at the
    # boundary (upstream deviates only by U+0387 / U+037E). Inside a unit:
    #
    # - DROPPED to an annotation (lossless, never passage text):
    #   <note> → "notes" [{text, type}] (editorial asides: "(scr. Δίδυμος)");
    #   <seg rend="Marginalia"> → "marginalia" (Diogenes' margin signs,
    #   ">" / "⸖" beside Homeric lines, "στρ." strophe labels);
    #   <bibl type="fragment-source"> → "fragment_source" (the modern
    #   citing-source label of a fragment: "Schol. Pindar. Pyth. V, 33");
    #   <del> → "deleted" (Leiden ⟦x⟧ — letters the witness struck:
    #   "ἄ⟦ι⟧νεται" reads ἄνεται). A dropped subtree contributes nothing
    #   to the passage — not even a break space (it may sit mid-word, as
    #   the deletion does; the EpiDoc apparatus rule).
    # - KEPT: <supplied> (editorial restoration 〈x〉/[x] — the edited
    #   text), <surplus> (Leiden {x}; in SC it brackets long stretches of
    #   genuine running text — Contra Celsum's proem opens inside one — so
    #   dropping it would delete text), <unclear>, <sic>, <head> inside a
    #   unit (the chronicle's own section heads "Κατακλυσμός."), a bare
    #   inline <bibl> (a printed locator "(19 F 17 a Sn.)"), <hi>, <quote>,
    #   <label>, <fw>, <g> and everything else not named here.
    # - BREAKS (one space, no text): lb, pb, cb, milestone, gap (Leiden
    #   lacuna — a single space, never invented dots), space, figure,
    #   caesura. lb/pb with break="no" join the word (SC's
    #   "προσελ<lb break="no"/>θόντων").
    # - BLOCKS (l, p, head, lg, item, div, ab, sp, speaker, label, list …)
    #   open and close with a space, so words never fuse across them.
    class CllgTeiParser < StreamingTeiParser
      # No refsDecl/citeStructure in the header — skip by rule.
      class NoCitationTree < Nabu::DocumentSkipped
        def initialize(message = nil)
          super(message, reason: "no citeStructure declared")
        end
      end

      # A declared tree whose levels match nothing in the body.
      class ZeroMatchTree < Nabu::DocumentSkipped
        def initialize(message = nil)
          super(message, reason: "declared citeStructure matches nothing")
        end
      end

      # One printed source edition from the sourceDesc (bibl or biblStruct).
      # +identifiers+: the bibl's typed idnos ({"ISBN" => …, "CPL" => …}).
      Edition = Data.define(:n, :title, :editors, :date, :publisher, :place, :series, :volume, :identifiers)

      # The header fields adapters mine, plus the citing tree (nil = none).
      Header = Data.define(:title, :author, :languages, :editions, :tree) do
        def cited? = !tree.nil?
      end

      # One compiled citeStructure level.
      Level = Data.define(:xpath, :use, :delim, :unit, :milestone)

      # An element as the XPath evaluator sees it.
      Frame = Data.define(:name, :attributes) do
        def initialize(name:, attributes: {})
          super
        end

        def [](attribute) = attributes[attribute]
      end

      MILESTONES = %w[milestone pb cb lb].freeze
      USES = ["@n", "position()"].freeze

      # The parsed passage-to-be (StreamingTeiParser's unit shape).
      Unit = Data.define(:citation, :text, :annotations)

      HEADER_END = "</teiHeader>"

      # The teiHeader alone (a byte slice, DOM-parsed — never the body).
      def self.header(path)
        doc = Nokogiri::XML(header_slice(path))
        doc.remove_namespaces!
        tei = doc.at_xpath("/TEI/teiHeader") or raise ParseError, "#{path}: no teiHeader"
        Header.new(
          title: squash(tei.at_xpath("fileDesc/titleStmt/title")&.text),
          author: squash(tei.at_xpath("fileDesc/titleStmt/author")&.text),
          languages: tei.xpath("profileDesc/langUsage/language/@ident").map { |attr| attr.value.strip },
          editions: tei.xpath("fileDesc/sourceDesc/bibl | fileDesc/sourceDesc/biblStruct").map { |node| edition(node) },
          tree: citing_tree(tei, path)
        )
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed teiHeader: #{e.message}"
      end

      # Lines up to </teiHeader> (both corpora are pretty-printed, so this
      # never reads into the body beyond one line), closed as a document.
      def self.header_slice(path)
        buffer = +""
        SourceRead.utf8_lines(path, label: "cllg teiHeader") do |line|
          buffer << line
          index = buffer.index(HEADER_END) or next
          return "#{buffer[0, index + HEADER_END.length]}</TEI>"
        end
        raise ParseError, "#{path}: no #{HEADER_END}"
      end

      def self.edition(node)
        date = node.at_xpath(".//date")
        title = node.at_xpath(".//title[@level='m']") || node.at_xpath(".//title[not(ancestor::series)]")
        Edition.new(
          n: node["n"],
          title: squash(title&.text),
          editors: node.xpath(".//editor[not(@role) or @role='editor']").map { |editor| squash(editor.text) }.uniq,
          date: squash(date && (date["when"] || date.text)),
          publisher: squash(node.at_xpath(".//publisher")&.text),
          place: squash(node.at_xpath(".//pubPlace")&.text),
          series: squash(node.at_xpath(".//series/title")&.text),
          volume: squash(node.at_xpath(".//series/biblScope[@unit='volume']")&.text),
          identifiers: node.xpath(".//idno[@type]").to_h { |idno| [idno["type"], squash(idno.text)] }.compact
        )
      end

      # default > unnamed > first; nil when the header declares none.
      def self.citing_tree(tei, path)
        decls = tei.xpath("encodingDesc/refsDecl[citeStructure]")
        decl = decls.find { |node| node["n"] == "default" } || decls.find { |node| node["n"].nil? } || decls.first
        return nil if decl.nil?

        levels = []
        node = decl.at_xpath("citeStructure")
        while node
          levels << level(node, path, depth: levels.size)
          node = node.at_xpath("citeStructure")
        end
        check_chain!(levels, path)
        levels
      end

      def self.level(node, path, depth:)
        use = node["use"].to_s.strip
        unless USES.include?(use)
          raise ParseError, "#{path}: unsupported citeStructure use #{use.inspect} (#{USES.join(' / ')})"
        end

        xpath = CiteXPath.compile(node["match"].to_s, path: path)
        if depth.zero? != xpath.absolute?
          raise ParseError, "#{path}: citeStructure level #{depth + 1} match #{node['match'].inspect} must be " \
                            "#{depth.zero? ? 'absolute' : 'relative'}"
        end
        Level.new(xpath: xpath, use: use, delim: node["delim"] || ".", unit: node["unit"],
                  milestone: MILESTONES.include?(xpath.leaf_name))
      end

      def self.check_chain!(levels, path)
        levels.each_cons(2) do |parent, child|
          next unless parent.milestone && !child.milestone

          raise ParseError, "#{path}: element citation level below a milestone level is unsupported " \
                            "(#{child.xpath.source.inspect} under #{parent.xpath.source.inspect})"
        end
      end

      def self.squash(value)
        text = value&.gsub(/[[:space:]]+/, " ")&.strip
        text.nil? || text.empty? ? nil : Normalize.nfc(text)
      end

      # Parse one edition file into a Nabu::Document. +header+ may be passed
      # when the caller already read it.
      def parse(source, urn:, language:, title: nil, metadata: {}, header: nil, license_override: nil)
        path = resolve_canonical_path(source, nil)
        header ||= self.class.header(path)
        raise NoCitationTree, "#{path}: the teiHeader declares no citeStructure" unless header.cited?

        units = extract(source, path: path, levels: header.tree)
        units = disambiguate_collisions(units)
        build_document(units, urn: urn, language: language, title: title || header.title, path: path,
                              metadata: metadata, license_override: license_override)
      end

      private

      def extraction_class = Extraction

      def no_passages_message = "the citation tree matched only empty units"

      # The Reader state machine: an element stack from the root (for the
      # absolute first-level paths), the open citation units (one slot per
      # level), and the drop/annotation capture.
      class Extraction < StreamingTeiParser::Walker
        DROPPED = { "note" => "notes", "del" => "deleted" }.freeze
        BREAKS = %w[lb pb cb milestone gap space figure caesura].freeze
        JOINABLE = %w[lb pb].freeze
        BLOCKS = %w[l p head lg item div ab sp speaker label list argument opener closer salute trailer
                    byline dateline epigraph].freeze

        # One open citation unit.
        Open = Struct.new(:level, :citation, :milestone, :depth, :context, :relaxed, :children,
                          :counters, :buffer, :annotations, keyword_init: true)

        # The attributes the text policy reads; the tree's predicates add theirs.
        POLICY_ATTRIBUTES = %w[n rend type break].freeze

        def initialize(reader:, path:, levels:)
          super(reader: reader, path: path)
          @levels = levels
          # Only the attributes something reads are copied off the Reader —
          # a full attribute hash per element is the hot cost on freed's GB.
          @attribute_names = (POLICY_ATTRIBUTES + levels.flat_map { |level| level.xpath.attribute_names }).uniq
          @stack = []
          @open = Array.new(levels.size)
          @root_counter = Hash.new(0)
          @units = []
          @matched = 0
          @in_body = false
          @drop = nil
        end

        def call
          @reader.each { |node| process(node) }
          close_from(0)
          raise ZeroMatchTree, "#{@path}: the declared citeStructure matched no citable node" if @matched.zero?

          @units
        end

        private

        def start_element(node)
          name = local_name(node)
          frame = Frame.new(name: name, attributes: attributes_of(node))
          @stack << frame
          if @drop
            @drop[:buffer] << " " if BREAKS.include?(name)
          elsif @in_body
            body_start(node, name, frame)
          elsif name == "body" && @stack.map(&:name) == %w[TEI text body]
            @in_body = true
          end
          @stack.pop if node.empty_element?
        end

        def attributes_of(node)
          return {} unless node.attributes?

          @attribute_names.each_with_object({}) do |attribute, found|
            value = node.attribute(attribute)
            found[attribute] = value if value
          end
        end

        def end_element(node)
          name = local_name(node)
          depth = @stack.size
          if @drop
            finish_drop if @drop[:depth] == depth
          elsif @in_body
            body_end(name, depth)
          end
          @stack.pop
        end

        def text_node(node)
          return unless @in_body

          if @drop
            @drop[:buffer] << node.value
          else
            target&.buffer&.<<(node.value)
          end
        end

        def body_start(node, name, frame)
          if (kind = drop_kind(name, frame))
            start_drop(kind, frame) unless node.empty_element?
            return
          end

          space if BREAKS.include?(name) && !(JOINABLE.include?(name) && frame["break"] == "no")
          space if BLOCKS.include?(name)
          cite(node, frame)
        end

        def body_end(name, depth)
          if name == "body"
            close_from(0)
            @in_body = false
            return
          end
          space if BLOCKS.include?(name)
          level = @open.index { |unit| unit && !unit.milestone && unit.depth == depth }
          close_from(level) if level
        end

        def drop_kind(name, frame)
          return DROPPED[name] if DROPPED.key?(name)
          return "marginalia" if name == "seg" && frame["rend"] == "Marginalia"

          "fragment_source" if name == "bibl" && frame["type"] == "fragment-source"
        end

        def start_drop(kind, frame)
          @drop = { kind: kind, depth: @stack.size, buffer: +"", type: frame["type"] }
        end

        def finish_drop
          drop = @drop
          @drop = nil
          unit = target or return
          text = drop[:buffer].gsub(/[[:space:]]+/, " ").strip
          return if text.empty?

          text = Normalize.nfc(text)
          record = drop[:kind] == "notes" ? { "text" => text, "type" => drop[:type] }.compact : text
          (unit.annotations[drop[:kind]] ||= []) << record
        end

        # -- citation ----------------------------------------------------------

        def cite(node, frame)
          level = matching_level or return
          spec = @levels[level]
          component = component_for(spec, level, frame) or return
          close_from(level) if spec.milestone || @open[level]
          open_unit(level, spec, component, node)
        end

        # The deepest level this element opens: children of the deepest open
        # unit first, then sibling milestones upward. Element levels already
        # open (a nested same-level match) are skipped — outermost wins.
        def matching_level
          deepest = @open.rindex { |unit| unit } || -1
          [deepest + 1, @levels.size - 1].min.downto(0) do |level|
            next if level.positive? && @open[level - 1].nil?

            spec = @levels[level]
            next if !spec.milestone && @open[level]
            return level if level_matches?(level, spec)
          end
          nil
        end

        def level_matches?(level, spec)
          return spec.xpath.matches?(@stack) if level.zero?

          parent = @open[level - 1]
          spec.xpath.matches?(@stack[(parent.context + 1)..], relaxed: parent.relaxed)
        end

        def component_for(spec, level, frame)
          if spec.use == "position()"
            counters = level.zero? ? @root_counter : @open[level - 1].counters
            return (counters[level] += 1).to_s
          end
          value = frame["n"]&.strip
          value unless value.nil? || value.empty?
        end

        def open_unit(level, spec, component, node)
          parent = level.zero? ? nil : @open[level - 1]
          parent.children += 1 if parent
          citation = parent ? "#{parent.citation}#{spec.delim}#{component}" : component
          element_depth = @stack.size
          @open[level] = Open.new(
            level: level, citation: citation, milestone: spec.milestone, depth: element_depth,
            context: spec.milestone ? milestone_context(parent) : element_depth - 1,
            relaxed: spec.milestone, children: 0, counters: Hash.new(0), buffer: +"", annotations: {}
          )
          @matched += 1
          close_from(level) if !spec.milestone && node.empty_element?
        end

        # A milestone unit's children read their relative path inside its
        # span: the element context is the one its parent read in.
        def milestone_context(parent)
          parent ? parent.context : -1
        end

        def close_from(level)
          (@open.size - 1).downto(level) do |index|
            unit = @open[index] or next
            @open[index] = nil
            emit(unit) if index == @levels.size - 1 || unit.children.zero?
          end
        end

        def emit(unit)
          return if unit.buffer.gsub(/[[:space:]]+/, "").empty?

          @units << Unit.new(citation: unit.citation, text: unit.buffer, annotations: unit.annotations)
        end

        def target
          @open.reverse_each { |unit| return unit if unit }
          nil
        end

        def space
          target&.buffer&.<<(" ")
        end
      end
      private_constant :Extraction

      # The citeStructure @match subset (class note). Compiled once per
      # level; #matches? tests a path of Frames ending at the candidate.
      class CiteXPath
        Step = Data.define(:axis, :name, :predicates)

        NAME = /\A(?:\*|[A-Za-z_][\w.-]*)/
        # Predicate tokens, one capture group per kind (#tokenize).
        TOKEN = /\s*(?:
          (\(|\)|=|!=)                          # punctuation
          | ('[^']*'|"[^"]*")                   # string literal
          | (@[A-Za-z_][\w.:-]*)                # attribute
          | (self::(?:\*|[A-Za-z_][\w.-]*))     # self axis
          | (not)(?=\s*\()                      # not(
          | (and|or)\b                          # connective
          | (\S+)                               # anything else: unsupported
        )/x
        private_constant :NAME, :TOKEN

        attr_reader :source, :steps

        def self.compile(source, path: nil)
          new(source, path: path)
        end

        def initialize(source, path: nil)
          @source = source.strip
          @path = path
          @absolute = @source.start_with?("/")
          @steps = parse_steps
        end

        def absolute? = @absolute

        def leaf_name = @steps.last.name

        # Every attribute a predicate reads.
        def attribute_names
          @steps.flat_map { |step| step.predicates.flat_map { |predicate| predicate_attributes(predicate) } }.uniq
        end

        # +frames+: the element path below the context node (the whole stack
        # from the root for an absolute path), the candidate last. +relaxed+
        # treats a leading child step as descendant (a milestone context:
        # the span, not an element, contains the candidate).
        def matches?(frames, relaxed: false)
          return false if frames.empty?

          match_from(@steps.size - 1, frames.size - 1, frames, relaxed)
        end

        private

        def predicate_attributes(node)
          case node
          in [:has | :eq | :ne, attribute, *] then [attribute]
          in [:or | :and, left, right] then predicate_attributes(left) + predicate_attributes(right)
          in [:not, inner] then predicate_attributes(inner)
          else []
          end
        end

        def match_from(step_index, frame_index, frames, relaxed)
          step = @steps[step_index]
          return false unless step_matches?(step, frames[frame_index])

          if step_index.zero?
            return true if step.axis == :descendant || relaxed

            return frame_index.zero?
          end
          return false if frame_index.zero?
          return match_from(step_index - 1, frame_index - 1, frames, relaxed) if step.axis == :child

          (frame_index - 1).downto(0).any? { |index| match_from(step_index - 1, index, frames, relaxed) }
        end

        def step_matches?(step, frame)
          (step.name == "*" || step.name == frame.name) &&
            step.predicates.all? { |predicate| evaluate(predicate, frame) }
        end

        def evaluate(node, frame)
          case node
          in [:or, left, right] then evaluate(left, frame) || evaluate(right, frame)
          in [:and, left, right] then evaluate(left, frame) && evaluate(right, frame)
          in [:not, inner] then !evaluate(inner, frame)
          in [:has, attribute] then !frame[attribute].nil?
          in [:eq, attribute, value] then frame[attribute] == value
          in [:ne, attribute, value] then !frame[attribute].nil? && frame[attribute] != value
          in [:self, name] then name == "*" || frame.name == name
          end
        end

        def parse_steps
          rest = @source.dup
          if rest.start_with?(".//", "./")
            rest = rest.delete_prefix(".")
          elsif !rest.start_with?("/")
            rest = "/#{rest}" # a bare relative step ("l") is a child step
          end
          steps = []
          until rest.empty?
            axis = rest.start_with?("//") ? :descendant : :child
            rest = rest.delete_prefix(axis == :descendant ? "//" : "/")
            name = rest[NAME] or unsupported!("expected a name test at #{rest.inspect}")
            rest = rest.delete_prefix(name)
            predicates = []
            while rest.start_with?("[")
              body, rest = take_bracket(rest)
              predicates << parse_expression(body)
            end
            unsupported!("unexpected #{rest.inspect}") unless rest.empty? || rest.start_with?("/")
            steps << Step.new(axis: axis, name: name, predicates: predicates)
          end
          unsupported!("empty path") if steps.empty?
          steps
        end

        # "[…]rest" → ["…", "rest"], quote- and nesting-aware.
        def take_bracket(text)
          depth = 0
          quote = nil
          text.each_char.with_index do |char, index|
            if quote
              quote = nil if char == quote
            elsif ["'", '"'].include?(char)
              quote = char
            elsif char == "["
              depth += 1
            elsif char == "]"
              depth -= 1
              return [text[1...index], text[(index + 1)..]] if depth.zero?
            end
          end
          unsupported!("unbalanced predicate")
        end

        def parse_expression(text)
          @tokens = tokenize(text)
          expression = parse_or
          unsupported!("trailing #{@tokens.map(&:last).join(' ')}") unless @tokens.empty?
          expression
        end

        def tokenize(text)
          tokens = []
          text.scan(TOKEN) do |punct, literal, attribute, self_axis, negation, connective, other|
            tokens << if punct then [:punct, punct]
                      elsif literal then [:literal, literal[1...-1]]
                      elsif attribute then [:attribute, attribute.delete_prefix("@")]
                      elsif self_axis then [:self, self_axis.delete_prefix("self::")]
                      elsif negation then [:not, negation]
                      elsif connective then [connective.to_sym, connective]
                      else unsupported!("token #{other.inspect}")
                      end
          end
          tokens
        end

        def parse_or
          left = parse_and
          while @tokens.first&.first == :or
            @tokens.shift
            left = [:or, left, parse_and]
          end
          left
        end

        def parse_and
          left = parse_unary
          while @tokens.first&.first == :and
            @tokens.shift
            left = [:and, left, parse_unary]
          end
          left
        end

        def parse_unary
          kind, value = @tokens.shift
          case kind
          when :not
            expect_punct("(")
            inner = parse_or
            expect_punct(")")
            [:not, inner]
          when :punct
            unsupported!("unexpected #{value.inspect}") unless value == "("
            inner = parse_or
            expect_punct(")")
            inner
          when :attribute then attribute_test(value)
          when :self then [:self, value]
          else unsupported!("unexpected #{value.inspect}")
          end
        end

        def attribute_test(attribute)
          operator = @tokens.first
          return [:has, attribute] unless operator&.first == :punct && %w[= !=].include?(operator.last)

          @tokens.shift
          kind, literal = @tokens.shift
          unsupported!("expected a literal after @#{attribute}#{operator.last}") unless kind == :literal
          [operator.last == "=" ? :eq : :ne, attribute, literal]
        end

        def expect_punct(punct)
          kind, value = @tokens.shift
          unsupported!("expected #{punct.inspect}") unless kind == :punct && value == punct
        end

        def unsupported!(why)
          where = @path ? "#{@path}: " : ""
          raise ParseError, "#{where}unsupported citeStructure match #{@source.inspect} (#{why})"
        end
      end
    end
  end
end
