# Net::Async::WebSearch House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

IO::Async multi-provider web search aggregator. Read first: the orchestrator's merge/dedup
path in `lib/Net/Async/WebSearch.pm` (`_select_providers` → `search`/`search_stream`/
`search_race` → `_normalize_url` → RRF) and the base class `Provider.pm`. Registration,
selection, merge and fetch are one mechanism; "looks orthogonal" is dangerous here.

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug anything under `lib/` or a provider | `net-async-websearch-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `net-async-websearch-release-manager` |
| Read-only research, audit, gap analysis | `net-async-websearch-worker` ("read-only, change nothing") |

Behavior-relevant = everything under `lib/`, the orchestrator's three modes, the provider base
class and every `::Provider::` backend, RRF merge, URL normalization/dedup, the Result
contract, the fetch pipeline, and the tests. Prose in `README.md` and `Changes` bullets are
not.

## Release

This distribution releases together with its siblings from local working state. A dep pin or
`$VERSION` ahead of what PAUSE indexed is expected; do not "fix" it or file it.

## Hazards

Short form; the reasons live in skill `net-async-websearch-core`.

- **`$loop->add($ws)` is mandatory** — omit it and every returned Future hangs with no error;
  providers are added as children with the parent, never added to the loop directly.
- **Dedup and ranking hide in the URL key** — `_normalize_url` (canonicalize → strip fragment
  → strip trailing slash → lowercase) is the identity for all three modes; a change there
  silently re-buckets results and shifts RRF scores. `$RRF_K = 60` behind `rrf_k` is likewise
  load-bearing — both are public behavior, not tuning knobs to touch casually.
- **A count-only test cannot catch the real failure** — a test that only checks a result count
  can't fail when dedup keys or RRF scoring break, which is the failure that reaches the caller.
- **`fetch => N` is additive, never filtering** — non-fetched results still appear without
  `$r->fetched`. `fetch_max_bytes` is enforced on the *decoded* body; `Net::Async::HTTP` does
  not cap the on-the-wire length, so a "cap" that assumes it will leak memory.
- **Live tests never run by default** — `t/50-live.t` is gated behind `TEST_WEBSEARCH_LIVE`
  and per-provider `TEST_WEBSEARCH_*` keys, deliberately so nobody hits real search APIs (and
  burns quota) by accident. The mock-driven suite is the only path; never widen a test to
  depend on a live var, never set one to make a suite "pass".
- **`our $VERSION` in all 11 modules, all identical** — this ships to CPAN, so the bundle
  rewrites every package; a per-file `$VERSION` is required and must not be collapsed to the
  main module. Every `.pm` also needs a `# ABSTRACT:` line for PodWeaver.

## Perl specifics — reference, don't restate

The architecture — the provider mesh, the three search modes, RRF merge, URL dedup and the
Result contract — lives in skill `net-async-websearch-core`; module loading, dependency
pinning and house style in `getty-perl-core`; the `IO::Async`/Future lifecycle in
`perl-io-async-future`; release conventions in `getty-perl-release-author-getty` +
`perl-release-dist-ini` (force-loaded per lane via `briefing.skills`).
