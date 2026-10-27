# Boots the read-only MCP server (bin/nabu mcp) for directory introspection
# checks. Without a synced library the server still starts: every tool
# answers with an honest missing-catalog note, so initialize/tools/list
# work in a sandbox. A real library needs the host's db/ and canonical/
# mounted in; this image deliberately ships none of them.
FROM ruby:3.3
RUN apt-get update -qq && apt-get install -y --no-install-recommends libsqlite3-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
CMD ["bin/nabu", "mcp"]
