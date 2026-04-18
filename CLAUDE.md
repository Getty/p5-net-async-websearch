# CLAUDE.md

Projekt-Guide für `Net::Async::WebSearch`. Die Workspace-Regeln in `../CLAUDE.md` gelten zusätzlich.

## Was ist das?

IO::Async-basierter Multi-Provider Web-Search-Aggregator. Eine Query fächert parallel zu DuckDuckGo, SearxNG, Brave, Serper, Google CSE, Yandex und Reddit, dedupliziert per normalisierter URL und merged via Reciprocal Rank Fusion.

Für API-Details, Modi (collect/stream/race), Selector-Semantik und das fetch=N Body-Retrieval → Skill `perl-net-async-websearch` laden.

## Layout

- `lib/Net/Async/WebSearch.pm` — Orchestrator
- `lib/Net/Async/WebSearch/Provider.pm` — Provider Base Class
- `lib/Net/Async/WebSearch/Provider/*.pm` — ein Modul pro Backend
- `lib/Net/Async/WebSearch/Result.pm` — Result-Contract
- `ex/search.pl` — Beispiel-CLI; `ex/searxng/` + `docker-compose.searxng.yml` für lokalen SearxNG
- `t/50-live.t` — Live-Tests (brauchen API-Keys, normalerweise übersprungen)

## Build & Test

```bash
dzil test              # volle Dist::Zilla Testsuite
prove -lv t/10-aggregation.t
```

Release läuft via `[@Author::GETTY]` Bundle (siehe `dist.ini`). Für Release-Workflow → Skill `perl-release-author-getty`.

## Async-Konventionen

IO::Async + Future/Future::AsyncAwait. Bei Lifecycle-/Cancellation-/Retention-Fragen → Skill `perl-io-async-future`.

## Neuen Provider hinzufügen

1. `lib/Net/Async/WebSearch/Provider/Foo.pm` als Subclass von `Net::Async::WebSearch::Provider`
2. Result-Contract aus `Result.pm` einhalten (normalisierte URL!)
3. Test in `t/` mit gemockten Responses; Live-Call höchstens nach `t/50-live.t`-Muster
