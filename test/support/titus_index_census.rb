# frozen_string_literal: true

module Nabu
  module TestSupport
    # The TITUS index-frame page census: an edition's part-selector frames
    # (<prefix>x1.htm, <prefix>x2.htm, …) list one <OPTION> per text page
    # (the frame's script opens page selectedIndex + 1 + its offset), so
    # the option count over an edition's frames IS its page count — the
    # number an adapter's discovery reconciles against at the first sync.
    module TitusIndexCensus
      def self.pages(edition_dir, prefix)
        Dir.glob(File.join(edition_dir, "#{prefix}x[0-9]*.htm")).sum do |path|
          File.binread(path).scan(/<OPTION\b/i).size
        end
      end
    end
  end
end
