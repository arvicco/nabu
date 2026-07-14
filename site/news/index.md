---
title: News
permalink: /news/
description: >-
  Release notes and library news — new sources, new capabilities, honest
  numbers — one entry per release or development phase, newest first.
---

One entry per release or development phase: what entered the library, what
the tools can now do, and the honest numbers as of each date. Entries are
added at every phase gate (the same pass that re-syncs the rest of this
site from the repository documentation). Subscribe by
[Atom feed]({{ '/feed.xml' | relative_url }}).

<ul class="news-list">
{% for post in site.posts %}
  <li>
    <span class="entry-date">{{ post.date | date: "%-d %B %Y" }}</span>
    <a href="{{ post.url | relative_url }}">{{ post.title }}</a>
    {% if post.description %}— {{ post.description | strip_newlines | strip }}{% endif %}
  </li>
{% endfor %}
</ul>
