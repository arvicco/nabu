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

  # Post times are public metadata, and any non-midnight time narrates
  # the clock behind the publish (one legacy post even carried a literal
  # +0200 offset — the owner's timezone, verbatim). Owner rule
  # 2026-11-03: every post is dated midnight UTC of its day — the date
  # is the finest public grain, and a midnight stamp can never trip the
  # future-dating trap above on its own publish date. Ordering within a
  # day falls to the filename, which is enough for a news page.
  def test_every_news_post_time_is_midnight_utc
    offenders = Dir.glob(File.join(POSTS_DIR, "*.md")).filter_map do |path|
      front = File.read(path)[/\A---\n.*?\n---/m].to_s
      date = front[/^date:\s*(.+)$/, 1] or next
      "#{File.basename(path)} (#{date.strip})" unless date.strip.match?(/\A\d{4}-\d{2}-\d{2} 00:00:00 \+0000\z/)
    end
    assert_empty offenders,
                 "post times narrate the working clock — date every post 'YYYY-MM-DD 00:00:00 +0000': " \
                 "#{offenders.join(', ')}"
  end

  CITATION = File.expand_path("../../CITATION.cff", __dir__)

  # The release-announcement guard (the release rail, docs/ops.md §12:
  # the news post rides the same change as the version bump). The moment
  # CITATION.cff names a version, some post's TITLE must announce it as
  # vX.Y.Z — a body-only mention ("since v1.7.0" in a later post) never
  # counts, or the next release could hide behind it. So a branch that
  # bumps `version:` goes red until its announcement is written, which is
  # exactly when the omission is still cheap to fix.
  def test_the_cited_version_has_an_announcement_post
    version = File.read(CITATION)[/^version:\s*"?(\d+\.\d+\.\d+)"?\s*$/, 1]
    refute_nil version, "CITATION.cff carries no X.Y.Z `version:` line"

    tag = announcement_tag(version)
    announcing = Dir.glob(File.join(POSTS_DIR, "*.md")).select do |path|
      front = File.read(path)[/\A---\n.*?\n---/m].to_s
      front[/^title:\s*(.+)$/, 1].to_s.match?(tag)
    end
    assert announcing.any?,
           "CITATION.cff says v#{version} but no news post title announces it — " \
           "write the release post under site/news/_posts/ in the same change as the bump"
  end

  def test_the_announcement_tag_does_not_match_a_longer_version
    tag = announcement_tag("1.7.0")
    assert_match tag, "v1.7.0 — the entity wave"
    refute_match tag, "v1.7.01 — a typo"
    refute_match tag, "v1.7.0.1 — a patch"
    refute_match tag, "nabu-data v11.7.0"
  end

  private

  def announcement_tag(version)
    /(?<![\w.])v#{Regexp.escape(version)}(?![\w.]*\d)/
  end
end
