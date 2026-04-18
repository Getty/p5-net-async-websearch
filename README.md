# Net::Async::WebSearch

`IO::Async` multi-provider web search aggregator. Fans a single query out to as many search providers as you register, deduplicates results by normalized URL, and either merges them with Reciprocal Rank Fusion, streams them as they arrive, or races for the fastest responder. Returns `Future` objects.

## Synopsis

```perl
use IO::Async::Loop;
use Net::Async::WebSearch;
use Net::Async::WebSearch::Provider::DuckDuckGo;
use Net::Async::WebSearch::Provider::SearxNG;
use Net::Async::WebSearch::Provider::Brave;
use Net::Async::WebSearch::Provider::Serper;

my $loop = IO::Async::Loop->new;
my $ws = Net::Async::WebSearch->new(
  providers => [
    Net::Async::WebSearch::Provider::DuckDuckGo->new( tags => ['free'] ),
    Net::Async::WebSearch::Provider::SearxNG->new(
      endpoint => 'https://searxng.example.org',
      tags     => ['free','private'],
    ),
    Net::Async::WebSearch::Provider::Brave->new(
      api_key => $ENV{BRAVE_API_KEY},
      tags    => ['paid'],
    ),
    Net::Async::WebSearch::Provider::Serper->new(
      api_key => $ENV{SERPER_API_KEY},
      tags    => ['paid','google-backed'],
    ),
  ],
);
$loop->add($ws);

# Collect mode: fan out, dedup, RRF-rank.
my $out = $ws->search(
  query   => 'handyintelligence AI consulting',
  limit   => 20,
  exclude => ['paid'],          # skip every provider tagged 'paid'
)->get;
# $out->{results}  — arrayref of Net::Async::WebSearch::Result, ranked
# $out->{errors}   — [{ provider, error }, ...]
# $out->{stats}    — { providers, providers_ok, providers_error, merged }

# Stream mode: fire per result as it arrives.
$ws->search(
  mode      => 'stream',
  query     => 'handy intelligence local AI infrastructure',
  on_result => sub {
    my $r = shift;
    say sprintf '[%s #%d] %s — %s', $r->provider, $r->rank, $r->title, $r->url;
  },
)->get;

# Race mode: first provider to return wins.
my $fast = $ws->search(
  query => 'handyintelligence',
  mode  => 'race',
  only  => [qw( brave serper )],
)->get;
```

## Providers

| Class (`Net::Async::WebSearch::Provider::...`) | Auth | Transport |
| --- | --- | --- |
| `DuckDuckGo`   | none                         | HTML scrape of `html.duckduckgo.com` |
| `SearxNG`      | optional Bearer token        | JSON (requires `&format=json` enabled on the instance) |
| `Brave`        | `X-Subscription-Token`       | JSON |
| `Serper`       | `X-API-KEY`                  | JSON, paid Google proxy |
| `Google`       | API key + `cx` (Programmable Search) | JSON, 10-results-per-call cap |
| `Yandex`       | Yandex Cloud API key + `folderid`    | XML (via XML::LibXML) |
| `Reddit`       | none                         | JSON (`/search.json`) |
| `Reddit::OAuth`| OAuth2 client_credentials / password / installed / authorization_code + refresh_token | JSON against `oauth.reddit.com` — see the module POD for the full app-setup guide |

### Getting API keys — cheat sheet

| Provider | Free tier | Credit card? | Where |
| --- | --- | --- | --- |
| DuckDuckGo | unlimited (HTML) | no | — |
| SearxNG | self-hosted | no | see `ex/docker-compose.searxng.yml` |
| **Brave** | $5 credits/month (~1000 q) | **yes** | [api.search.brave.com/app/dashboard](https://api.search.brave.com/app/dashboard) |
| **Serper** | 2500 queries on signup | no | [serper.dev](https://serper.dev) (key in dashboard) |
| **Google CSE** | 100 queries/day | no | [programmablesearchengine.google.com](https://programmablesearchengine.google.com) + Google Cloud Console (enable *Search the entire web* in engine settings for full-web coverage) |
| **Yandex** | Cloud trial credits | no | [console.yandex.cloud/link/search-api/](https://console.yandex.cloud/link/search-api/) — needs Cloud folder + service account with `search-api.executor` |
| Reddit (keyless) | rate-limited | no | — |
| Reddit OAuth | 100 QPM per client_id, free | no | [reddit.com/prefs/apps](https://www.reddit.com/prefs/apps) |

## Stacking providers

Register multiple instances of the same class — five SearxNG mirrors, two Serper API keys, a private DuckDuckGo clone alongside the public one. `add_provider` auto-renames colliding instances (`serper`, `serper#2`, `serper#3`…) so every one stays addressable. Tag them with `tags => [...]` to group them:

```perl
Net::Async::WebSearch::Provider::Serper->new(
  name    => 'serper-primary',
  api_key => $K1,
  tags    => ['paid'],
);
Net::Async::WebSearch::Provider::Serper->new(
  name    => 'serper-backup',
  api_key => $K2,
  tags    => ['paid'],
);

$ws->search( query => $q, exclude => ['paid'] );   # both Serpers skipped
$ws->search( query => $q, only    => ['searxng'] );# every SearxNG instance
$ws->search( query => $q,
  provider_opts => {
    paid             => { limit => 5 },            # all tagged 'paid'
    'serper-primary' => { tbs   => 'qdr:w' },      # exact name wins
  },
);
```

Selectors in `only`, `exclude`, and `provider_opts` keys match against three things on each provider: its `name`, its class leaf (`searxng`, `serper`, …), and any of its `tags`.

## Normalized result fields

Every provider promises these fields on the returned `Net::Async::WebSearch::Result` (some may be `undef` when the upstream doesn't supply them):

- `url`, `title`, `snippet`, `provider`, `rank`
- `domain` — auto-derived from the URL
- `score` — aggregate RRF score (only set by `collect` mode)

Optional when available: `published_at` (ISO 8601 or upstream-native string), `language` (BCP-47), `nsfw`.

Provider-specific extras (subreddit, sitelinks, MIME type, engine name, …) live in `$r->extra`. Raw upstream payload, when retained, lives in `$r->raw`.

## Fetching result bodies

Pass `fetch => N` to any of the search modes to additionally GET the top N result URLs and attach the response to each Result under `$r->fetched`. You still get the full result list — fetch is additive. Use-cases: RAG, crawling, summarization. Not needed for pure MCP-style consumers.

```perl
my $out = $ws->search(
  query => 'handyintelligence AI workshops',
  limit => 20,
  fetch => 5,           # GET the top 5 URLs after RRF ranking
  fetch_timeout    => 10,
  fetch_max_bytes  => 500_000,
  fetch_user_agent => 'my-crawler/1.0',
)->get;

for my $r ( @{ $out->{results} } ) {
  next unless $r->fetched && $r->fetched->{ok};
  say $r->url, ' → ', length $r->fetched->{body}, ' bytes';
}
```

In stream mode you can also pass `on_fetch => sub { ... }` to react to each fetched body as it completes.

### Concurrency

Two knobs (set on the main `Net::Async::WebSearch` instance, overridable per call):

- `fetch_concurrency` — global cap on parallel in-flight fetches (default **100**).
- `fetch_concurrency_per_target_ip` — per-host cap (default **5**), wired to `Net::Async::HTTP`'s `max_connections_per_host`. Currently per-hostname, not per-resolved-IP.

## Modes at a glance

- **collect** (default) — wait for every selected provider, dedup by normalized URL, score with Reciprocal Rank Fusion, return the top `limit`.
- **stream** — fire `on_result` the moment each provider's results arrive, dedup on the fly. The returned Future resolves when every provider has settled.
- **race** — resolve with the first provider to return successfully. Falls through to `{ errors }` only if everyone fails.

## See also

- [Net::Async::HTTP](https://metacpan.org/pod/Net::Async::HTTP)
- [Future](https://metacpan.org/pod/Future)
- [IO::Async](https://metacpan.org/pod/IO::Async)
