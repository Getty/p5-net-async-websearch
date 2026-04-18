---
name: perl-net-async-websearch
description: |
  Load when using Net::Async::WebSearch — the IO::Async multi-provider web
  search aggregator that fans a single query out across DuckDuckGo, SearxNG,
  Brave, Serper, Google CSE, Yandex, and Reddit, deduplicates by normalized
  URL, and merges via Reciprocal Rank Fusion. Covers the three modes
  (collect / stream / race), provider stacking with tags and name-collision
  rules, selector semantics (only / exclude / provider_opts), the
  Net::Async::WebSearch::Result contract, and the additive fetch=N body
  retrieval with its concurrency knobs.
---

# Net::Async::WebSearch

`Net::Async::WebSearch` is an `IO::Async::Notifier` subclass that takes a
query, fans it out to every registered provider in parallel, and either
merges, streams, or races the results. All methods return `Future`s.

## Construction

```perl
use IO::Async::Loop;
use Net::Async::WebSearch;

my $loop = IO::Async::Loop->new;
my $ws = Net::Async::WebSearch->new(
  providers => [ ... Provider objects ... ],
  # fetch_concurrency               => 100,  # global parallel fetch cap
  # fetch_concurrency_per_target_ip => 5,    # per-host cap (hostname, not IP)
);
$loop->add($ws);
```

**Must `$loop->add($ws)`** — it's a Notifier. Providers are added to the
loop automatically when the parent is added.

## Three search modes

`$ws->search(mode => ..., query => $q, ...)` returns a Future whose
resolution shape depends on `mode`:

### `mode => 'collect'` (default) → Future[\%out]

Wait for every selected provider. Dedup by normalized URL. Score with RRF.
Trim to `limit`.

```perl
{
  results => [ Net::Async::WebSearch::Result, ... ],   # RRF-ranked, $r->score set
  errors  => [ { provider => $name, error => $err }, ... ],
  stats   => { providers => N, providers_ok => A, providers_error => B, merged => M },
}
```

### `mode => 'stream'` → Future[\%out]

Fires `on_result => sub { $result }` as each provider's results arrive,
dedup on the fly. Future resolves when every provider has settled. Final
`results` is still populated. Also supports `on_fetch` when `fetch => N`.

### `mode => 'race'` → Future[\%out]

First provider to return **successfully** wins. Only falls through to
`{ errors }` when every provider fails. Use `only => [...]` to restrict
racers.

## Provider stacking & selectors

Register multiple instances of the same class (five SearxNG mirrors, two
Serper keys, …). `add_provider` renames collisions to `serper`, `serper#2`,
`serper#3`, ...

Selectors in `only`, `exclude`, and `provider_opts` keys match three things
on each provider:
1. its `name` (`serper-primary`, `serper#2`)
2. its **class leaf** (`serper`, `searxng`, `duckduckgo`, `google`, `yandex`, `brave`, `reddit`)
3. any of its `tags` (`free`, `paid`, `private`, whatever you set)

```perl
$ws->search( query => $q, exclude => ['paid'] );
$ws->search( query => $q, only    => ['searxng'] );
$ws->search( query => $q,
  provider_opts => {
    paid             => { limit => 5 },       # tag — applies to all paid
    'serper-primary' => { tbs   => 'qdr:w' }, # exact name — wins over tag
  },
);
```

Exact name > class leaf > tag when merging per-provider opts.

## Providers

| Class (`::Provider::...`) | Auth | Transport |
|---|---|---|
| `DuckDuckGo` | none | HTML scrape |
| `SearxNG` | optional Bearer | JSON (instance must have `format=json` enabled) |
| `Brave` | `X-Subscription-Token` | JSON |
| `Serper` | `X-API-KEY` | JSON (Google proxy) |
| `Google` | API key + `cx` | JSON, 10-result cap per call |
| `Yandex` | Cloud API key + `folderid` | XML via XML::LibXML |
| `Reddit` | none | JSON `/search.json` |
| `Reddit::OAuth` | OAuth2 (multiple grant types) | JSON against `oauth.reddit.com` |

## Result contract

Every `Net::Async::WebSearch::Result` **guarantees**: `url`, `title`,
`snippet`, `provider`, `rank`, `domain` (auto-derived).

**Optional** (may be `undef`): `published_at`, `language` (BCP-47), `nsfw`.

**Mode-specific**: `score` only set in `collect` mode (the RRF score).
**Fetch-specific**: `fetched` only set when `fetch => N` was passed.

Provider-specific extras (subreddit, sitelinks, engine name, …) live in
`$r->extra`. Upstream raw payload — if retained — lives in `$r->raw`.

## `fetch => N` — additive body retrieval

Passing `fetch => N` GETs the top N result URLs after ranking and attaches
the response to `$r->fetched`. You always still get the full results list
— fetch is **additive**, never filtering.

```perl
my $out = $ws->search(
  query            => $q,
  fetch            => 5,
  fetch_timeout    => 10,
  fetch_max_bytes  => 500_000,
  fetch_user_agent => 'my-crawler/1.0',
)->get;

for my $r ( @{ $out->{results} } ) {
  next unless $r->fetched && $r->fetched->{ok};
  ...
}
```

Two concurrency knobs (on the `Net::Async::WebSearch` instance, per-call
overridable):

- `fetch_concurrency` — global in-flight cap (default **100**).
- `fetch_concurrency_per_target_ip` — per-host cap (default **5**), wired
  to `Net::Async::HTTP`'s `max_connections_per_host`. **Per-hostname, not
  per-resolved-IP** — the name is aspirational.

In `stream` mode, pass `on_fetch => sub { $result }` to react as each body
completes.

## Common pitfalls

- Forgetting `$loop->add($ws)` → Futures hang.
- Expecting `$r->score` in `stream`/`race` output — only `collect` sets it.
- Expecting `fetch` to filter results — it doesn't. Non-fetched results
  still appear without `$r->fetched`.
- Selecting by class leaf when you have multiple of that class — all match.
  Use `name` for a single instance.
- SearxNG returning HTML instead of JSON → the instance didn't enable
  `format=json` in `settings.yml`.
- Google CSE returning <10 results total → `limit > 10` requires multiple
  API calls; Google caps each at 10.
- Yandex needing `folderid` AND a service account with role
  `search-api.executor` — missing either returns opaque auth errors.

## When NOT to load this skill

- For generic `IO::Async` / `Future` lifecycle — load `perl-io-async-future`.
- For web scraping / crawling (not search) — load `perl-firecrawl` or the
  `perl-net-async-firecrawl` skill for the async client.
