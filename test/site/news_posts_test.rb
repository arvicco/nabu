# frozen_string_literal: true

require "test_helper"
require "time"

# News-post visibility guard (owner report 2026-07-22: the v1.2.0 release
# "went completely unannounced" — three posts carried future timestamps,
# and Jekyll SILENTLY drops future-dated posts, so the announcements were
# committed, merged, deployed… and invisible on the live site). A post's
# front-matter date must be in the past at commit time; ordering within a
# day is expressed with past times, never by post-dating.
class NewsPostsTest < Minitest::Test
  POSTS_DIR = File.expand_path("../../site/news/_posts", __dir__)

  def test_every_news_post_is_dated_in_the_past
    offenders = Dir.glob(File.join(POSTS_DIR, "*.md")).filter_map do |path|
      front = File.read(path)[/\A---\n.*?\n---/m] or next "#{File.basename(path)} (no front matter)"
      date = front[/^date:\s*(.+)$/, 1] or next "#{File.basename(path)} (no date)"
      stamp = Time.parse(date)
      "#{File.basename(path)} (#{date.strip})" if stamp > Time.now
    end
    assert_empty offenders,
                 "future-dated posts are SILENTLY INVISIBLE on the Jekyll site — " \
                 "re-date to a past time: #{offenders.join(', ')}"
  end
end
