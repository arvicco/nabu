# frozen_string_literal: true

require "cgi"

require_relative "../normalize"

module Nabu
  module Adapters
    # The CoNLL-U FEATS join for Coptic Scriptorium (the v2 path the survey
    # and the adapter header deferred). The TT layer stays the source of
    # record (CopticTtParser), but upstream's UD feature bundle — Definite,
    # Gender, Number, Person, PronType, VerbForm, Mood, Polarity, Poss,
    # NumType… — rides ONLY in the CoNLL-U export beside it: the TT tagset
    # carries no inflection, the word form does. Each TT chunk has a twin of
    # the same basename under its corpus's *_CONLLU dir (sahidic.ot: a
    # *_CONLLU.zip member), and the twin's word lines are the same tokens
    # in the same order — so the join is positional, VERIFIED by form.
    #
    # == The alignment census (v6.2.0, all 2,497 non-excluded TT chunks)
    #
    # Every chunk has a twin. 227 are "\n\n" placeholders (sahidica.nt's
    # automatic chapters) — absent. Of the rest, 2,267 align exactly by form
    # once the CoNLL-U form is decoded the way TT attributes are (HTML
    # entities unescaped — "ϫⲟⲩϩ&lt;ⲉ&gt;" in three sahidic.ot chapters — and
    # NFC — johannes-canons/life-longinus write U+0387 where the TT's NFC
    # has U+00B7): 2,068,809 tokens, 1,009,543 carrying features. 2 do not
    # align (magical-papyri OCrum_ST_18 and p_CtYBR_1800, whose CoNLL-U
    # drops the final token) — exact-or-nothing: a misaligned twin joins NO
    # feature, because a shifted join would hang every bundle on the wrong
    # word. One chunk is the source's standing quarantine.
    #
    # A joined token gains "feats" (the UD string verbatim, "_" = none) —
    # the key the morph façade's unscoped UD row already reads, so
    # `--morph person=2,number=pl` reaches Coptic with no façade change.
    module CopticConlluFeats
      # One CoNLL-U word line: the decoded form and its FEATS (nil for "_").
      Word = Data.define(:form, :feats)

      WORD_ID = /\A\d+\z/

      module_function

      # The word lines of +text+ (range lines "1-3", empty nodes, comments
      # and blanks skipped), in file order.
      def words(text)
        text.to_s.each_line.filter_map do |line|
          cells = line.chomp.split("\t")
          next unless cells.size == 10 && cells[0].match?(WORD_ID)

          Word.new(form: form(cells[1]), feats: cells[5] == "_" ? nil : cells[5])
        end
      end

      # A CoNLL-U form decoded like a TT attribute (class note).
      def form(raw)
        Normalize.nfc(CGI.unescapeHTML(raw.to_s))
      end

      # Join +words+ onto the tokens of +units+ (CopticTtParser::Unit
      # values, file order): :absent when there are no words (no twin, or a
      # placeholder), :misaligned when the word and token sequences differ
      # in length or any form (nothing joined), else :joined.
      def join!(units, words)
        return :absent if words.nil? || words.empty?

        tokens = units.flat_map { |unit| unit.annotations["tokens"] || [] }
        return :misaligned unless tokens.size == words.size &&
                                  tokens.zip(words).all? { |token, word| token["form"] == word.form }

        tokens.zip(words).each { |token, word| token["feats"] = word.feats if word.feats }
        :joined
      end
    end
  end
end
