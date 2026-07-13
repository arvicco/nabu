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
| Nightly | `nabu backup` | local disk loss — the attic protects against *upstream* deletion, not a dead SSD (§9) | `com.nabu.backup-nightly` |
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
- **`nabu health --remote`** — no-clone upstream probe. The strategy is keyed
  per source off the adapter: **git** sources use `git ls-remote` (liveness,
  HEAD-vs-`last_sync_sha` drift, best-effort license-drift via
  raw.githubusercontent); **HTTP-zip** sources (ORACC) HEAD each project zip
  (200 = reachable; `Last-Modified` vs the stored `.zip-fetch.json` pin =
  drift) and GET each project `metadata.json` for license-drift — through the
  same vendored-cert path ZipFetch fetches on. A never-synced project reads
  *never-synced*, not gone. **Exit 1** iff any upstream is *gone*;
  *moved*/*behind*/*license changed* are reported but stay exit 0. (ORACC's
  standalone `metadata.json` currently serves an empty body over HTTP, so its
  license row reads *unchecked* until upstream serves it — the drift check via
  the zip `Last-Modified` is unaffected.) Drift vocabulary (P15-7): *current* /
  *behind* / *unpinned* (synced before the pins ledger existed — see backfill
  below) / *never-synced* (genuinely untouched: no pin, no run, no canonical
  tree) / *frozen* (a frozen-policy source — no drift is expected, matching
  `status`'s `up=frozen`). Every `--remote` run also **persists** each source's
  verdict into the history ledger (the `source_probes` cache, one row per
  source, survives `nabu rebuild`), which is what feeds the `up=` column in
  `nabu status` (below) — so between probe runs you can still see, offline,
  whether an upstream had moved.

  **`license_watch` (P16-5):** a source with `license_watch: <url>` in
  `config/sources.yml` has its license checked against THAT url instead of
  the strategy default — the escape hatch for upstreams whose terms live in
  a README or a repository record page (kielipankki `README.txt`, clarin.si
  records, the PROIEL-family repo READMEs) that the github-only LICENSE
  fetch and the ORACC `metadata.json` GET can't see. The probe GETs the url
  (any host, same vendored-cert client, no redirect following),
  sha256-hashes the body, and compares against a baseline on a ledger pin
  keyed by the watched url: first sight records it (*baseline recorded*), a
  match reads *license: ok*, a mismatch reads *license: CHANGED* naming the
  url. A fetch failure reads unchecked (silent per the P16-0 rule), never an
  error. Candidate urls for the currently-unwatchable sources sit as
  comments in `sources.yml`; flipping one on is an OWNER decision (verify
  the url serves the terms directly first). Non-configured sources are
  untouched.
- **`nabu health --backfill-pins`** — one-shot pin recovery, **no network**.
  Sources fetched before the pins ledger existed (P7) have a canonical clone
  but no ledger pin, so drift reads *unpinned*. This records the pin from what
  is already on disk: for a git source, `git -C canonical/<slug> rev-parse
  HEAD`; for a non-git ZipFetch/FileFetch source, the `sha256` in its
  `.zip-fetch.json` / `.file-fetch.json` state file. **Read-only** on
  `canonical/`; writes **only** the ledger pins; **idempotent** (a source that
  already carries a pin is skipped). After a backfill, those sources read
  *current* / *behind* against a real pin instead of *unpinned* — or you can
  just let the next `nabu sync` record the pin.
- **`nabu status`** — per-source row: on/off, sync policy, an **`up=` upstream
  column** (P14-12), live doc/passage (or dictionary-entry) counts, and the last
  run. The `up=` column is read from the probe cache, never a live network call:
  - `up=ok(2d)` — current as of a probe 2 days ago (quiet; the age is always shown);
  - `up=BEHIND(2d)` — upstream moved past our sync pin (**loud** — a sync is due);
  - `up=stale(30d)` — the last probe is older than two weeks, so even its "ok" is
    too old to trust; re-probe before deciding;
  - `up=?(never)` — never probed here (run `nabu status --remote`);
  - `up=?(3d)` — probed, but drift is indeterminate (unpinned / never synced /
    upstream unreachable / multi-repo with no pins yet); an *unpinned* source
    clears once `nabu health --backfill-pins` or the next sync records its pin;
  - `up=frozen` — a frozen-policy dead-project snapshot; no probe is expected.
- **`nabu status --remote`** — the **one-command informed-update flow**: run the
  live upstream probe inline (the same code path as `health --remote`, so it also
  persists the cache), then render the freshly refreshed `up=` column. Use this
  when you want an on-demand "has anything upstream actually changed?" before
  deciding to sync. MCP `nabu_status` surfaces the same cached verdict per source
  (an `upstream` object) but **never probes live** — it is a bounded status read.
- **`rake fixtures:check`** — re-fetches the small fixture samples, diffs them,
  re-runs the affected adapter tests. Never overwrites. Nonzero on drift.
- **`nabu backup`** — file-level rsync of canonical/ (attic included), the
  history ledger, config/, and (default-on) the derived dbs to a mounted
  external volume. Read-only on canonical/. **Exit 1** if the target volume is
  not mounted (the mount-point guard, §9) or any rsync section fails. Full
  detail — the external-volume workflow, the guard, restore, the drill — is §9.

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
| `com.nabu.backup-nightly` | daily 02:30 | `StartCalendarInterval` `Hour`/`Minute` |
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
log/backup-nightly.out.log        log/backup-nightly.err.log
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

### `nabu status` shows `up=BEHIND` (or you want to check before syncing)
`up=BEHIND(Nd)` means the last probe found upstream had moved past our sync pin —
a sync is due, and now it's an *informed* one. If the column reads `up=?(never)`
or `up=stale(Nd)`, the cache can't answer "did it change?"; run `nabu status
--remote` to probe inline and refresh the column in one command, then decide.
This is the whole point of the column: an update is a choice you can see the
reason for, not a blind weekly ritual.

### `health --remote` shows a gone / moved / license-changed upstream
- **GONE (exit 1)** — the upstream probe failed: `git ls-remote` for a git
  source, or a non-200/non-redirect HEAD on a project zip for an HTTP-zip
  source (ORACC). Check the URL/repo by hand: did the org rename, the repo
  move, or the project die? If it's dead, set `sync_policy: frozen` in
  `config/sources.yml` (stop hitting it; keep what you have — retained docs
  stay live and searchable). If it moved, update the `upstream_url` (git) or
  the project list / URL shape (HTTP-zip).
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
bundle exec bin/nabu backup                                   # nightly (§9)
bundle exec bin/nabu verify                                   # nightly
bundle exec bin/nabu sync --all && \
  bundle exec bin/nabu health && \
  bundle exec bin/nabu health --remote                        # weekly
bundle exec rake fixtures:check                               # monthly (optional)
bundle exec rake ops:drill                                    # restore drill (§9)

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

---

## 9. Backup & the restore drill (P7-2)

The attic (architecture §8) protects the corpus against *upstream* deletion.
It does **nothing** for *local* disk loss — a dead SSD takes canonical/, the
history ledger, and the derived dbs with it. `nabu backup` is the answer the
concept always promised: **"restorable from an rsync backup with zero
services."** File-level, no database dump, no daemon — just files on another
disk that a bare `rsync` (or Finder drag) could restore.

### What gets backed up (the non-derivable set)

| Section | Source | Why it is in the set |
|---|---|---|
| `canonical/` | the corpus tree | The permanent asset — **including every `.attic/`** |
| `db/history.sqlite3` | the ledger (P7-1) | Run history, sync pins, license baselines, durable revisions — the **only** copy |
| `config/` | nabu.yml + sources.yml | The registry that defines what the corpus *is* |
| `db/catalog.sqlite3`, `db/fulltext.sqlite3` | the derived dbs | **Default-on** — a file copy beats an hour of rebuild; `--skip-derived` omits them |

**Why file-level, not git mirrors.** The obvious "back up canonical/ by pushing
each slug's git to a bare mirror" silently drops the `.attic/` — it is a plain
directory inside the working tree, not a branch or a tracked path, and it holds
the documents that exist **nowhere else** (upstream scrapped them; the clone is
`--depth 1`). File-level rsync copies the attic for free. So: file-level, or the
backup is a lie.

The derived dbs are cheap insurance. Restoring them means the corpus is queryable
the instant the rsync finishes; omit them with `--skip-derived` and a single
`nabu rebuild` reconstitutes them from canonical/ byte-for-byte.

**WAL sidecars (P17-7).** The dbs run `journal_mode=WAL` (architecture §5), so
while any connection is open a `<db>-wal` file next to each db holds recently
committed transactions the main file does not yet contain (plus a `<db>-shm`
index). Each db section copies its live sidecars along with the db — the main
file alone would be a stale or torn snapshot — and **prunes** a sidecar at the
target whose source counterpart has been checkpointed away (restoring an
outdated `-wal` next to a newer main file would replay old frames over newer
data). Normally the nightly backup finds no sidecars at all: the last closing
connection checkpoints the WAL and removes them. A backup that overlaps a
running sync/rebuild can still capture a mid-write snapshot — same as before
WAL — which is exactly what `rake ops:drill` exists to catch; prefer the
nightly timing or re-run after the write finishes.

### The target: a mounted external volume

The destination is a path **under a mounted external volume**, wired in
`config/nabu.yml`:

```yaml
backup:
  target: /Volumes/NabuBackup/nabu
```

`--to PATH` overrides it per-run. The owner points this at the real backup disk;
swapping to different hardware later is **just this one line** — no code change.

Until the real disk is wired, a **virtual volume** simulates it exactly (same
`/Volumes` mount-point semantics, so the guard and the workflow are identical):

```sh
# Create a 20 GB APFS sparsebundle (grows as needed; adjust -size to taste).
hdiutil create -size 20g -type SPARSEBUNDLE -fs APFS \
  -volname NabuBackup "$HOME/NabuBackup.sparsebundle"

# Attach it — mounts at /Volumes/NabuBackup.
hdiutil attach "$HOME/NabuBackup.sparsebundle"

# Detach when done (or before ejecting/unplugging the real disk later).
hdiutil detach /Volumes/NabuBackup
```

With the volume attached, `backup: target: /Volumes/NabuBackup/nabu` and a plain
`nabu backup` works. When real hardware arrives, `hdiutil detach`, plug in the
disk (it mounts under `/Volumes/<name>`), and change the one config line.

### The mount-point guard (why an unmounted target is refused)

This is the difference between a backup and a silent disaster. If the volume is
**not** mounted, `/Volumes/NabuBackup` is either absent or — worse — a bare empty
directory sitting on the **boot disk**. An unguarded `rsync` would happily write
the entire corpus there, reporting success, filling your boot disk; and then when
the real volume *does* mount, its mountpoint is **shadowed** by that stale
directory. You discover the problem when you need the backup and it isn't there.

So before any rsync, `nabu backup` verifies the target lives on a **real mount
point**: it ascends from the target to its volume root and checks that the
volume root's device id differs from its parent's (a genuine mount boundary). A
target on the boot disk ascends all the way to `/` with no device change — its
"volume root" is `/`, which is refused:

```
$ nabu backup                 # volume detached
backup: volume not mounted — refusing to back up onto the boot disk.
The target /Volumes/NabuBackup/nabu is not on a mounted external volume. …
(exit 1)
```

`--allow-unmounted` bypasses the guard for a **deliberately** local target (the
drill uses it; a same-disk scratch copy might too). Never pass it to the nightly
job — a failed nightly backup because the disk is detached is a *feature*: it
shows up red in the log instead of quietly corrupting your only copy.

`rsync -a --delete` is scoped to each section's **subdirectory** of the target
(`…/nabu/canonical`, `…/nabu/config`, `…/nabu/db`), never to the volume root —
so a file sitting beside the target is never swept, and even with the guard
bypassed the blast radius is contained.

### Usage

```sh
nabu backup                       # to the configured volume (guarded)
nabu backup --to /Volumes/X/nabu  # explicit target
nabu backup --dry-run             # print the rsync plan, change nothing
nabu backup --skip-derived        # canonical + ledger + config only
```

Each run prints one line per section (files, size, duration) and a summary; any
section's failure makes the whole run exit 1 with an honest per-section report.

### Restore procedure (fresh machine, step by step)

The promise is a machine with *nothing* but a clone and the backup disk:

1. **Clone the repo and install deps** (this brings the code, the migrations,
   and the *committed* config — but not your data):
   ```sh
   git clone <nabu-repo-url> nabu && cd nabu
   bundle install
   ```
2. **Attach the backup volume** (`hdiutil attach …` for the sparsebundle, or
   just plug in the real disk).
3. **rsync the data back** from the backup into the checkout:
   ```sh
   rsync -a /Volumes/NabuBackup/nabu/canonical/  ./canonical/
   rsync -a /Volumes/NabuBackup/nabu/db/         ./db/
   rsync -a /Volumes/NabuBackup/nabu/config/     ./config/
   ```
   (Restoring *into a different root*? Point nabu at it without editing code:
   `export NABU_ROOT=/restored NABU_CONFIG=/restored/config/nabu.yml` and run
   the commands below from anywhere — `Config.load` honours both.)
4. **Bring up the derived layer.** Two honest options:
   - **Trust the restored derived dbs** (fastest — they came along by default):
     do nothing; `nabu status` / `nabu search` work immediately.
   - **Rebuild from canonical** (the belt-and-suspenders proof, and mandatory if
     you restored with `--skip-derived`):
     ```sh
     bundle exec bin/nabu rebuild
     ```
     Rebuild drops and re-derives catalog + fulltext from canonical/ alone; the
     ledger (history.sqlite3) is *never* touched, so run history/pins/baselines
     survive.
5. **Verify integrity:**
   ```sh
   bundle exec bin/nabu verify     # re-hash canonical against the catalog → exit 0 clean
   bundle exec bin/nabu health     # trends + golden-query replay against the live corpus
   ```

That is the whole fresh-machine path: clone, install, rsync, (rebuild), verify.
No services, no database server, no cloud.

### The restore drill — prove it without waiting for a disaster

`rake ops:drill` runs that entire chain **locally, against a throwaway copy**, so
you never find out at 3 a.m. that the backup wasn't restorable:

```sh
bundle exec rake ops:drill
```

It backs up the live tree to a tmp target (`--allow-unmounted`, because the tmp
target is same-disk on purpose), **restores** into a fresh tmp "machine",
**rebuilds** the derived db from the restored canonical/ alone, **verifies**,
**replays** the golden queries, and cross-checks the restored document/passage
counts against the source of truth (the live catalog). It only **reads** the
live corpus — backup is read-only on its sources — and writes exclusively under
a tmp workspace, so it is safe to run against the live install any time. Output:

```
Restore drill
  backup     → /…/target  (5/5 sections, 61347 files, OK)
  restore    → /…/machine
  rebuild    quarantined 0 document(s)
  verify     clean
  golden     6 found, 0 lost, 0 skipped
  counts     source=61347 docs / 920766 passages  restored=61347 docs / 920766 passages  MATCH
  => RESTORABLE
```

A non-zero exit (`NOT RESTORABLE`) means the backup would not restore cleanly —
investigate before trusting it. Run the drill after any change to the backup set,
the loader, or the rebuild path.

### The nightly backup job

`ops/launchd/com.nabu.backup-nightly.plist` runs `nabu backup` nightly (02:30 by
default, before the 03:15 verify). Install it exactly like the others (§3),
substituting the same two placeholders:

```sh
LABEL="com.nabu.backup-nightly"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
sed -e "s#__NABU_ROOT__#$NABU_ROOT#g" \
    -e "s#__RUBY_BIN_DIR__#$RUBY_BIN_DIR#g" \
    "$NABU_ROOT/ops/launchd/$LABEL.plist" > "$DEST"
plutil -lint "$DEST"
launchctl bootstrap "gui/$(id -u)" "$DEST"
launchctl kickstart -k "gui/$(id -u)/$LABEL"        # fire once now to prove it
```

Because the guard exits 1 when the volume is detached, a nightly fire while the
backup disk is unplugged lands as a clear failure in
`log/backup-nightly.err.log` — exactly the signal you want. Wire an ntfy hook
(§7) on that job if you want to be pushed the news.

---

## 10. Reads during a sync/rebuild (WAL, P17-7)

Reading the corpus while a sync, rebuild, or batch producer writes is
**supported and safe**. Every nabu SQLite file runs `journal_mode=WAL`
(persisted in the file; set idempotently on every read-write connect, so
pre-WAL dbs flip on their first open by current code), which gives N readers +
1 writer concurrently: readers see a stable snapshot, the writer never waits
for them. This closed the 2026-07-13 defect where a lingering `sqlite3
-readonly` session crashed a running `nabu rebuild` with
`SQLite3::BusyException` — in the old rollback-journal mode one reader's
shared lock could kill the writer's commit.

Ground rules:

- `nabu search/show/status` and MCP tools during an owner sync/rebuild:
  fine. You read the last committed snapshot; the writer proceeds.
- **Ad-hoc inspection: `sqlite3 -readonly` NO LONGER OPENS a WAL db when no
  writer has it open** (a readonly handle cannot create the `-shm` sidecar —
  found live 2026-07-13, first WAL flip). The inspection convention is now
  `sqlite3 db/<file>.sqlite3 "PRAGMA query_only=ON; SELECT …"` — reads
  succeed, any write attempt errors at the SQL layer ("attempt to write a
  readonly database", verified). `-readonly` still works while a writer
  holds the db (the sidecars exist then), but don't rely on the timing.
- Every connection (readonly included) carries a **10 s busy timeout**
  (`Store::BUSY_TIMEOUT_MS`), which covers what WAL does not: two *writers*
  overlapping (a batch producer committing while a sync runs) wait each other
  out instead of crashing — but don't *schedule* concurrent writers; the
  timeout is a shock absorber, not a queue.
- Expect `<db>-wal`/`<db>-shm` sidecar files next to each db while any
  connection is open; the last connection to close checkpoints and removes
  them. Never delete or separate a `-wal` from its db by hand — backup handles
  the pair (§9).
