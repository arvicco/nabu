# Operating Nabu — the maintenance cadence

This is the runbook for keeping a Nabu install healthy over years of intermittent
attention. It wires the cadence in `docs/maintenance-and-extension.md` §1 to
concrete launchd jobs and tells you how to install them, read their output, and
react when one goes red.

The design premise (maintenance §1): *pick it back up after three months and
nothing has rotted.* The jobs below are the tripwires that make that true.

Everything here assumes a working checkout: `bundle install` has run, `bin/nabu
version` prints a version, and at least one `nabu sync` (or `nabu rebuild`) has
built `db/`.

---

## 1. The cadence at a glance

| Frequency | Command | What it guards against | Job |
|---|---|---|---|
| Nightly | `nabu verify` | bitrot / tamper — canonical files silently changing under the catalog | `com.nabu.verify-nightly` |
| Weekly | `nabu sync --all` → `nabu health` → `nabu health --remote` | upstream drift, quarantine spikes, dead/moved/relicensed upstreams | `com.nabu.weekly-maintenance` |
| Monthly *(optional)* | `rake fixtures:check` | upstream **format** drift the fixtures no longer match | `com.nabu.fixtures-monthly` |
| Quarterly / Yearly | manual review (runs anomalies, gem/RuboCop updates, license re-verify) | rot the automation can't see | — (by hand) |

What each command does and its exit contract:

- **`nabu verify`** — re-parses every canonical file and compares content hashes
  against the catalog. Read-only, no network. **Exit 0** clean; **exit 1** on any
  mismatch / missing / unparseable document, with the offending URNs listed.
- **`nabu sync --all`** — fetches and loads every *enabled*, `sync_policy: live`
  source. Network + writes `canonical/` and `db/`. The >20% withdrawal
  circuit-breaker aborts (exit 1) any source whose sync would gut it. One
  source's failure does not stop the others.
- **`nabu health`** — local, no network. Run-history trends (quarantine spikes,
  added-count collapse, withdrawal/retirement creep, stale sources) plus a live
  golden-query replay. **Exit 1** on a loud finding (spike, >15% creep, a lost
  golden query); soft warnings (collapse, 5–15% creep, stale) stay **exit 0**.
- **`nabu health --remote`** — no-clone upstream probe (`git ls-remote`
  liveness, HEAD-vs-`last_sync_sha` drift, best-effort license-drift). **Exit 1**
  iff any upstream is *gone*; *moved*/*behind*/*license changed* are reported but
  stay exit 0.
- **`rake fixtures:check`** — re-fetches the small fixture samples, diffs them,
  re-runs the affected adapter tests. Never overwrites. Nonzero on drift.

### What is NOT automated (on purpose)

Per `CLAUDE.md`, **real syncs stay eyeball-verified events.** The weekly
`sync --all` job exists for you to enable *deliberately* once you're comfortable
letting it run unattended — it is not on by default. The circuit-breaker is a
guard, not a substitute for occasionally watching a run and spot-checking a few
passages (`nabu status`, `nabu show`). If in doubt, leave the weekly job
uninstalled and run `nabu sync --all` by hand.

The nightly `verify` job is safe to run unattended without reservation — it only
reads.

---

## 2. Why launchd needs help finding Ruby

This is the one genuinely fiddly part; get it right and the rest is mechanical.

A launchd job runs with **none of your interactive shell's setup**: no
`~/.zprofile`, no Homebrew `PATH`, no rbenv/chruby shims, no `bundle` on `PATH`.
Its `PATH` is a bare `/usr/bin:/bin:/usr/sbin:/sbin`, where `ruby` is macOS's
ancient system Ruby — the wrong interpreter. A job that just says `bundle exec
bin/nabu verify` will fail with "command not found: bundle" or load the wrong
Ruby.

The templates solve this by **naming the Ruby/bundle bindir explicitly** in the
job's environment:

```xml
<key>WorkingDirectory</key>
<string>__NABU_ROOT__</string>
<key>EnvironmentVariables</key>
<dict>
  <key>PATH</key>
  <string>__RUBY_BIN_DIR__:/usr/bin:/bin:/usr/sbin:/sbin</string>
</dict>
<key>ProgramArguments</key>
<array>
  <string>/bin/sh</string>
  <string>-c</string>
  <string>exec bundle exec bin/nabu verify</string>
</array>
```

With `__RUBY_BIN_DIR__` prepended to `PATH`:

- `bundle` resolves to your real bundler,
- `bin/nabu`'s `#!/usr/bin/env ruby` shebang finds the matching interpreter,
- `git` (which `sync` shells out to) resolves from `/usr/bin`.

And `WorkingDirectory: __NABU_ROOT__` lets Bundler find the `Gemfile` and the
adapters find `canonical/`.

### Finding your `__RUBY_BIN_DIR__`

From inside the repo, ask the same Ruby the suite uses:

```sh
cd /path/to/nabu
dirname "$(which ruby)"          # Homebrew: /opt/homebrew/bin
```

- **Homebrew** (this box): `/opt/homebrew/bin`.
- **rbenv:** point at the concrete version's bin, **not** the shim dir — shims
  need `rbenv init` which the job won't run:
  `dirname "$(rbenv which ruby)"` → e.g. `~/.rbenv/versions/3.3.5/bin`.
- **chruby / asdf:** likewise the concrete install's `bin`.

> Note on this box specifically: bare `rake` resolves to the wrong Ruby, which is
> why every command goes through `bundle exec` and the job pins the bindir. If
> you upgrade Ruby, update `__RUBY_BIN_DIR__` in the installed plists (rbenv
> version bumps move the path).

---

## 3. Installing a job

The plists in `ops/launchd/` are **templates** — nothing here is auto-installed.
Installing is: substitute the two placeholders, drop the file in
`~/Library/LaunchAgents/`, and `bootstrap` it.

Placeholders (identical across all three templates):

| Placeholder | Value |
|---|---|
| `__NABU_ROOT__` | absolute path to this checkout, e.g. `/Users/vb/Dev/nabu` |
| `__RUBY_BIN_DIR__` | the Ruby/bundle bindir from §2, e.g. `/opt/homebrew/bin` |

Install the nightly verify job (the safe one to start with):

```sh
NABU_ROOT="/Users/vb/Dev/nabu"
RUBY_BIN_DIR="$(cd "$NABU_ROOT" && dirname "$(which ruby)")"
LABEL="com.nabu.verify-nightly"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"

sed -e "s#__NABU_ROOT__#$NABU_ROOT#g" \
    -e "s#__RUBY_BIN_DIR__#$RUBY_BIN_DIR#g" \
    "$NABU_ROOT/ops/launchd/$LABEL.plist" > "$DEST"

# Sanity-check the substituted plist before loading it.
plutil -lint "$DEST"

# Load it into your GUI login session's domain.
launchctl bootstrap "gui/$(id -u)" "$DEST"
```

`sed` with `#` delimiters avoids clashing with the `/` in the paths. Repeat for
`com.nabu.weekly-maintenance` and (optionally) `com.nabu.fixtures-monthly` by
changing `LABEL` — but read §1's warning before enabling the weekly sync.

### Test-fire a job immediately (don't wait for the calendar)

`bootstrap` only *schedules* the job; it won't run until its
`StartCalendarInterval`. To prove it works now:

```sh
launchctl kickstart -k "gui/$(id -u)/com.nabu.verify-nightly"
```

`-k` kills any running copy first and starts a fresh one. Then read the logs
(§5). This is the acceptance test for a freshly installed job.

Inspect a loaded job:

```sh
launchctl print "gui/$(id -u)/com.nabu.verify-nightly"   # full state, last exit code
launchctl list | grep com.nabu                            # quick "is it loaded" check
```

### Uninstall

```sh
launchctl bootout "gui/$(id -u)/com.nabu.verify-nightly"
rm "$HOME/Library/LaunchAgents/com.nabu.verify-nightly.plist"
```

`bootout` unloads it from the running session; removing the file stops it
reloading at next login. Editing an installed plist requires a
`bootout` + `bootstrap` cycle to take effect (launchd caches the loaded copy).

---

## 4. Scheduling knobs

The templates ship with sensible, adjustable times:

| Job | Default schedule | Key |
|---|---|---|
| `com.nabu.verify-nightly` | daily 03:15 | `StartCalendarInterval` `Hour`/`Minute` |
| `com.nabu.weekly-maintenance` | Sundays 04:00 | `Weekday` `0` + `Hour`/`Minute` |
| `com.nabu.fixtures-monthly` | 1st of month 05:00 | `Day` `1` + `Hour`/`Minute` |

Notes:

- `Weekday` is `0`–`7` with both `0` and `7` meaning Sunday.
- A job missed because the Mac was **asleep or powered off** runs shortly after
  wake — launchd fires a `StartCalendarInterval` job once on the next
  opportunity, it does not queue every missed slot.
- Times are local. Keep the nightly job comfortably before the weekly one if you
  ever put both on the same night.
- `ProcessType: Background` (set in every template) tells the scheduler these are
  low-priority; they won't fight foreground work for CPU/IO.

---

## 5. Reading results

Each job redirects stdout and stderr to the repo's **gitignored** `log/` dir:

```
log/verify-nightly.out.log        log/verify-nightly.err.log
log/weekly-maintenance.out.log    log/weekly-maintenance.err.log
log/fixtures-monthly.out.log      log/fixtures-monthly.err.log
```

`.out.log` holds the normal report (the same text you'd see running the command
by hand); `.err.log` holds Thor's failure summary when the command exits nonzero.
launchd **appends** across runs and never rotates — truncate them yourself if
they grow (`: > log/verify-nightly.out.log`), or add a `newsyslog`/logrotate rule.

The **exit code** is the machine-readable verdict. launchd records the last
exit status; read it with:

```sh
launchctl print "gui/$(id -u)/com.nabu.verify-nightly" | grep -i 'last exit'
```

Exit-code contract recap: `verify` → 1 on any hash mismatch; `health` → 1 on a
loud finding; `health --remote` → 1 only if an upstream is gone; `sync --all` →
per-source, a tripped breaker aborts that source. The weekly job runs its three
commands regardless of each other's exit code, so scan the whole `.out.log`, not
just the tail.

---

## 6. What to do when a job goes red

Match the symptom to the failure class:

### `verify` reports a MISMATCH / MISSING / UNPARSEABLE
A canonical file changed out from under the catalog. This is the bitrot/tamper
alarm.
- **MISMATCH** — the file's content no longer hashes to what the catalog
  recorded. Suspect **disk trouble or tampering** first (canonical is the
  permanent asset; nothing but a sync should ever rewrite it). Check disk SMART
  status and your backups. If the change is *intended* (you edited canonical by
  hand — rare), reconcile by rebuilding: `nabu rebuild` re-derives `db/` from
  canonical so the hashes match again.
- **MISSING** — a canonical file the catalog expects is gone. Restore it from
  backup or the source's git history, then `nabu rebuild`.
- **UNPARSEABLE** — a file that used to parse no longer does; likely corruption.
  Same drill: restore + rebuild.
- Remember: `db/` is disposable (`nabu rebuild` regenerates it). `canonical/` is
  not — protect it. The attic protects against *upstream* deletion, **not local
  disk loss; backups remain the answer** (maintenance §7, architecture §8).

### `health` shows a loud ANOMALY (exit 1)
Read the report — it names the source and the signal.
- **quarantine spike** — a sync suddenly quarantined far more documents than its
  history. Usually an **upstream format change** broke a parser. Reproduce with
  `nabu sync <slug> --parse-only` (no network), inspect a quarantined file, fix
  the adapter/parser, re-run. Do **not** accept the run until the count returns
  to baseline.
- **withdrawal/retirement creep >15%** — slow upstream bleed the per-sync 20%
  breaker never trips on. Check `nabu health --remote` and the source's upstream:
  is it shrinking legitimately, or restructuring? Consider `sync_policy: frozen`
  if the project is winding down.
- **golden query lost** — a known query stopped returning its expected passage.
  This is a loader/normalizer/indexer regression the unit tests missed. Bisect
  recent changes; `nabu rebuild` to rule out a stale index.

### `health --remote` shows a gone / moved / license-changed upstream
- **GONE (exit 1)** — `git ls-remote` failed. Check the URL/repo by hand: did
  the org rename, the repo move, or the project die? If it's dead, set
  `sync_policy: frozen` in `config/sources.yml` (stop hitting it; keep what you
  have — retained docs stay live and searchable). If it moved, update the
  `upstream_url`.
- **MOVED** — best-effort redirect signal; the stored URL may be stale. Update
  it when convenient.
- **license CHANGED** — the upstream LICENSE file's hash differs from the
  recorded baseline. **Review it before the next sync.** A relicense (e.g. a
  source going non-commercial or restricted) may mean you should freeze the
  source rather than keep ingesting under terms you haven't accepted. Retained
  docs keep the license they were fetched under (conventions §7); new fetches
  would land under the new one.

### `sync --all` aborted a source (circuit-breaker)
An upstream restructure looked like a mass deletion (>20% of docs). The sync
wrote **nothing** for that source (the tree is left byte-unchanged before the
breaker). Investigate the upstream diff by hand; if the deletion is real and
intended, re-run that source with `nabu sync <slug> --force`. If it's a
restructure/rename, the attic + rename detection should have handled it —
re-run without `--force` and check `nabu status` for retired counts.

---

## 7. Notifications (optional, owner-configured)

**The templates only write logs. Nothing notifies you by default** — no ntfy, no
email, no webhook is wired. To get pushed a message on failure, add it yourself.

The simplest approach: wrap the command so a nonzero exit fires a webhook. For
example, to ping [ntfy.sh](https://ntfy.sh) when the nightly verify fails, change
that job's `ProgramArguments` script to:

```xml
<key>ProgramArguments</key>
<array>
  <string>/bin/sh</string>
  <string>-c</string>
  <string>bundle exec bin/nabu verify || curl -fsS -H "Title: nabu verify FAILED" -d "check log/verify-nightly.err.log" https://ntfy.sh/YOUR-PRIVATE-TOPIC</string>
</array>
```

The `|| curl …` runs only on a nonzero exit, so you hear about failures and stay
quiet on success. Any webhook works (Slack incoming webhook, a self-hosted ntfy,
`osascript -e 'display notification …'` for a local banner) — swap the `curl`.
For the weekly job, wrap the whole three-command block or notify per command;
because those run regardless of each other's exit, capture the exit codes if you
want a combined verdict.

This is left to you deliberately: notification endpoints are personal, contain
secrets (topic URLs, tokens), and don't belong in a committed template.

---

## 8. Quick reference

```sh
# Run the cadence by hand (no launchd needed):
bundle exec bin/nabu verify                                   # nightly
bundle exec bin/nabu sync --all && \
  bundle exec bin/nabu health && \
  bundle exec bin/nabu health --remote                        # weekly
bundle exec rake fixtures:check                               # monthly (optional)

# Install / test-fire / remove a job (repeat per label):
sed -e "s#__NABU_ROOT__#$PWD#g" \
    -e "s#__RUBY_BIN_DIR__#$(dirname "$(which ruby)")#g" \
    ops/launchd/com.nabu.verify-nightly.plist \
    > ~/Library/LaunchAgents/com.nabu.verify-nightly.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.nabu.verify-nightly.plist
launchctl kickstart -k "gui/$(id -u)/com.nabu.verify-nightly"   # fire now
launchctl print "gui/$(id -u)/com.nabu.verify-nightly"          # inspect
launchctl bootout "gui/$(id -u)/com.nabu.verify-nightly"        # uninstall
```
