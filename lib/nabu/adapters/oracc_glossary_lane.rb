# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # The ORACC glossary lane (P104-4, Q81 — the №R-69a pilot of the
    # secondary dictionary lane, Adapter.dictionary_lane): each in-scope
    # project's per-language glossary (<project>/gloss-<lang>.json — the
    # signature-indexed lemma list the corpusjson l-nodes reference) is
    # dictionary-shaped content riding the SAME canonical tree the tablet
    # documents come from. One dictionary per (project, language code from
    # the filename — sux, akk, akk-x-mbperi, xur, qpn…), slug
    # oracc-<project-slug>-<lang>; entries keep the glossary's own entry
    # ids (the loader's stable upsert key within a build — a re-parse of
    # the same bytes always re-mints them).
    #
    # A dictionary-shaped sub-adapter, not a source: no manifest, no fetch
    # (the Oracc zip fetch already landed the files). #discover/#parse are
    # the whole surface, which is exactly what DictionaryLoader#load_from
    # drives — and subclassing Nabu::Adapter keeps discover_with_attic's
    # retention overlay (an upstream-dropped glossary keeps loading from
    # the attic like any other content file).
    #
    # == Large files: streamed, never JSON.parse'd whole
    #
    # The 368 live gloss files total 2.2 GB and the worst
    # (epsd2/admin/ur3 gloss-sux.json) is 625 MB — but its "entries"
    # array is only ~33 MB (5.0%, measured 2026-09-26); the rest is the
    # "instances"/"summaries" signature→occurrence maps this lane never
    # needs. A whole-file JSON.parse would materialize those too (multi-GB
    # of transient heap for the worst file). EntryStream reads
    # sequentially in 1 MiB chunks, yields each entry object individually,
    # and STOPS at the entries array's close — peak per-file memory is the
    # built DictionaryDocument, never the file (measured on the worst
    # case, 2026-09-26: 2,716 entries streamed in 1.4 s at ~140 MB RSS;
    # the 124 MB epsd2/literary gloss-sux, 3,605 entries, in 2.8 s). Files
    # load one at a time through the loader — never all 368 at once.
    class OraccGlossaryLane < Nabu::Adapter
      GLOSS_GLOB = "gloss-*.json"

      # One ref per non-empty gloss file across the in-scope projects
      # (Oracc::PROJECTS — the lane's cone IS the adapter's cone), at
      # either unpack depth (the nested-root shape, Oracc#project_dir):
      # gloss files sit beside metadata.json at the project content root.
      # id = oracc-gloss:<project-slug>:<lang> — stable, one per
      # dictionary, identical for the attic copy of a scrapped file (so
      # live-wins dedup holds). An absent cone yields nothing, honestly.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Oracc::PROJECTS.flat_map { |project| project_refs(workdir, project) }
                       .sort_by(&:id).each(&block)
      end

      # Stream one glossary file into one DictionaryDocument. The header's
      # own lang field is cross-checked against the filename's code — a
      # divergence would mis-shelve every entry, so it stops the file
      # loudly (quarantine) instead of mislabeling.
      def parse(document_ref)
        lang = document_ref.metadata.fetch("lang")
        project = document_ref.metadata.fetch("project")
        document = Nabu::DictionaryDocument.new(
          slug: "oracc-#{project}-#{lang}", language: lang,
          title: "ORACC glossary — #{document_ref.metadata.fetch('project_path')} (#{lang})",
          canonical_path: document_ref.path
        )
        stream = EntryStream.new(document_ref.path)
        stream.each_entry do |raw|
          check_header!(stream.header, lang)
          document << build_entry(raw, lang)
        end
        document
      rescue Nabu::ValidationError, EntryStream::Malformed => e
        raise Nabu::ParseError, "oracc glossary #{document_ref.id}: #{e.message}"
      end

      private

      def project_refs(workdir, project)
        slug = project.tr("/", "-")
        base = File.join(workdir, slug)
        nested = File.join(base, *project.split("/").drop(1))
        [base, nested].uniq.flat_map { |dir| Dir.glob(File.join(dir, GLOSS_GLOB)) }
                           .reject { |path| File.empty?(path) }
                           .map { |path| gloss_ref(project, slug, path) }
      end

      def gloss_ref(project, slug, path)
        lang = File.basename(path, ".json").delete_prefix("gloss-")
        Nabu::DocumentRef.new(
          source_id: Oracc::MANIFEST.id,
          id: "oracc-gloss:#{slug}:#{lang}",
          path: File.expand_path(path),
          metadata: { "project" => slug, "project_path" => project, "lang" => lang }
        )
      end

      # The header cross-check runs on the FIRST entry (the stream has the
      # header by then); a lang divergence between filename and payload
      # would shelve entries under the wrong dictionary language.
      def check_header!(header, lang)
        upstream = header["lang"].to_s
        return if upstream.empty? || upstream == lang

        raise EntryStream::Malformed, "filename says #{lang.inspect} " \
                                      "but the payload's lang field says #{upstream.inspect}"
      end

      # cf is the citation form ("adam"), gw the guide word
      # ("habitation"), headword the composite key ("adam[habitation]N").
      # All NFC at this boundary; the folded lookup key is the one minted
      # search form (conventions §9), per the dictionary's language.
      def build_entry(raw, language)
        entry_id = raw["id"].to_s.strip
        composite = Normalize.nfc(raw["headword"].to_s)
        raise EntryStream::Malformed, "glossary entry without an id (headword #{composite.inspect})" if entry_id.empty?

        cf = Normalize.nfc(raw["cf"].to_s)
        headword = cf.empty? ? composite : cf
        raise EntryStream::Malformed, "glossary entry #{entry_id} has no headword" if headword.strip.empty?

        gw = Normalize.nfc(raw["gw"].to_s)
        folded = Normalize.search_form(headword, language: language)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: composite.empty? ? headword : composite, language: language,
          headword: headword, headword_folded: folded.nil? || folded.empty? ? headword : folded,
          gloss: gw.empty? ? nil : gw, body: entry_body(raw, headword, gw)
        )
      end

      # A compact plain-text body: headline (headword — guide word (pos)),
      # one line per sense, the attested written forms. Deterministic and
      # NFC; the raw composite headword stands in when a sparse entry
      # carries nothing else.
      def entry_body(raw, headword, guide_word)
        pos = raw["pos"].to_s.strip
        headline = [headword, guide_word.empty? ? nil : guide_word].compact.join(" — ")
        headline = "#{headline} (#{pos})" unless pos.empty?
        lines = [headline]
        Array(raw["senses"]).each do |sense|
          next unless sense.is_a?(Hash)

          mng = sense["mng"].to_s.strip
          next if mng.empty?

          lines << [sense["num"].to_s.strip, mng].reject(&:empty?).join(" ")
        end
        forms = Array(raw["forms"]).filter_map { |form| form["n"] if form.is_a?(Hash) }.uniq
        lines << "forms: #{forms.join(', ')}" unless forms.empty?
        Normalize.nfc(lines.uniq.join("\n"))
      end

      # Incremental string-aware scan of one glossary file (see the class
      # note for why): parses the scalar header members (everything before
      # the top-level "entries" key), then yields each element of the
      # entries array as its own parsed Hash, and stops — the
      # instances/summaries mass after the array is never read. Structural
      # scanning is regex-jump based (String#index / anchored match), so
      # the per-byte work stays in C; the buffer is compacted as entries
      # are consumed, bounding memory at one chunk plus one entry.
      class EntryStream
        # Damage in the byte stream (truncation, non-JSON) — the lane
        # wraps it into Nabu::ParseError, quarantining the file.
        class Malformed < Nabu::Error; end

        CHUNK = 1 << 20
        # Structural characters at scan level; ':' and ',' matter only for
        # the header's key/value alternation.
        HEADER_STEP = /["{}\[\]:,]/
        OBJECT_STEP = /["{}\[\]]/
        # From just after an opening quote to the closing quote, escapes
        # respected; anchored so a partial string at buffer end fails and
        # triggers a refill.
        STRING_REST = /\G(?:\\.|[^"\\])*"/m

        # The scalar members preceding "entries" ({"type" => "glossary",
        # "project" => ..., "lang" => ...}); populated once scanning
        # reaches the entries key — i.e. before the first yield.
        attr_reader :header

        def initialize(path)
          @path = path
        end

        def each_entry
          File.open(@path, "rb") do |io|
            @io = io
            @buffer = String.new(encoding: Encoding::BINARY)
            @pos = 0
            scan_header!
            skip_ws!
            expect!("[")
            loop do
              skip_ws!
              case peek!
              when "]" then break
              when "," then @pos += 1
              when "{"
                yield JSON.parse(object_slice!)
                compact!
              else raise Malformed, "unexpected #{peek!.inspect} inside the entries array of #{@path}"
              end
            end
          end
          self
        end

        private

        # Walk the top level until the "entries" key's ':' — tracking
        # depth and the object key/value alternation so a VALUE string
        # spelled "entries" (or a nested key) can never fool it — then
        # close the consumed prefix into the header hash.
        def scan_header!
          depth = 0
          key = key_start = nil
          expecting_key = false
          loop do
            case char = find!(HEADER_STEP)
            when '"'
              start = @pos
              @pos += 1
              value = string!
              if depth == 1 && expecting_key
                key = value
                key_start = start
              end
            when "{", "["
              depth += 1
              expecting_key = char == "{"
              @pos += 1
            when "}", "]"
              depth -= 1
              @pos += 1
            when ":"
              @pos += 1
              return (@header = parse_header(key_start)) if depth == 1 && key == "entries"

              expecting_key = false
            when ","
              expecting_key = true
              @pos += 1
            end
          end
        end

        # The bytes before the "entries" key are complete member pairs —
        # strip the trailing comma, close the brace, parse.
        def parse_header(entries_key_start)
          raise Malformed, "no top-level entries key found in #{@path}" if entries_key_start.nil?

          prefix = @buffer[0...entries_key_start].force_encoding(Encoding::UTF_8)
          JSON.parse("#{prefix.rstrip.sub(/,\z/, '')}}")
        rescue JSON::ParserError => e
          raise Malformed, "malformed glossary header in #{@path}: #{e.message}"
        end

        # The complete object starting at @pos ('{' .. matching '}'),
        # strings skipped wholesale, sliced as UTF-8 for JSON.parse.
        def object_slice!
          start = @pos
          depth = 0
          loop do
            case find!(OBJECT_STEP)
            when '"' then (@pos += 1
                           string!)
            when "{", "[" then (depth += 1
                                @pos += 1)
            when "}", "]"
              depth -= 1
              @pos += 1
              return @buffer[start...@pos].force_encoding(Encoding::UTF_8) if depth.zero?
            end
          end
        end

        # Advance @pos to the next match of +step+ (refilling as needed)
        # and return the character there.
        def find!(step)
          loop do
            index = @buffer.index(step, @pos)
            if index
              @pos = index
              return @buffer[index]
            end
            @pos = @buffer.bytesize # nothing structural behind; only new bytes can match
            refill!
          end
        end

        # Consume a string body from just after its opening quote; returns
        # the raw content (escapes intact — only ever compared against
        # plain ASCII key names).
        def string!
          loop do
            if (match = STRING_REST.match(@buffer, @pos))
              @pos += match[0].bytesize
              return match[0].chomp('"')
            end
            refill!
          end
        end

        def skip_ws!
          @pos += 1 while peek!.match?(/\s/)
        end

        def peek!
          refill! while @pos >= @buffer.bytesize
          @buffer[@pos]
        end

        def expect!(char)
          actual = peek!
          raise Malformed, "expected #{char.inspect}, got #{actual.inspect} in #{@path}" unless actual == char

          @pos += 1
        end

        # In string! the escape-aware match must resume from the STRING's
        # start, so @pos is left untouched across a refill; everywhere
        # else @pos only moves forward. Drop consumed bytes after each
        # yielded entry so the buffer never accretes the whole array.
        def refill!
          chunk = @io.read(CHUNK)
          raise Malformed, "truncated glossary JSON in #{@path} (EOF mid-scan)" if chunk.nil?

          @buffer << chunk
        end

        def compact!
          return if @pos < CHUNK

          @buffer.slice!(0, @pos)
          @pos = 0
        end
      end
    end
  end
end
