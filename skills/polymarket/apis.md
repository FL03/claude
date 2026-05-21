---
name: polymarket:apis
description: |
  Polymarket API endpoint reference. Base URLs, request/response shapes,
  pagination, rate limits, and gotchas for the Gamma (market discovery),
  CLOB (order book + trading), Data (analytics), and Relayer (gasless tx)
  APIs. Context7-grounded against docs.polymarket.com/api-reference/*.
  Load when implementing API calls or debugging request shapes.
type: reference
version: 5.1.0
---

# APIs — Endpoint Reference

Four public APIs cover the full Polymarket surface. All run on the Polygon
mainnet (chainId 137). All write paths require L2 auth except `/auth/*` which
requires L1. Staging mirrors live at `clob-staging.polymarket.com`.

| API | Base URL | Auth | Purpose |
|---|---|---|---|
| Gamma | `https://gamma-api.polymarket.com` | none | Market & event discovery |
| CLOB  | `https://clob.polymarket.com` | L2 for writes | Order book, trading, market metadata |
| Data  | `https://data-api.polymarket.com` | none | User positions, trades, leaderboards |
| Relayer | `https://relayer-v2.polymarket.com` | builder or relayer API key | Gasless tx submission |

---

## 1. Gamma API — Market Discovery

Read-only, public, fast. The right entry point for "find markets matching X".

### Core endpoints

| Method | Path | Use |
|---|---|---|
| GET | `/events` | List events with filter + sort |
| GET | `/events/{id}` | One event by id |
| GET | `/markets` | List markets (slug, condition_id, event_id filters) |
| GET | `/markets?slug={slug}&limit=1` | Resolve a slug to full market detail |
| GET | `/tags` | Tag taxonomy |
| GET | `/series` | Recurring market series |

### Common `/events` query patterns

```
# active markets by 24h volume
?closed=false&active=true&order=volume24hr&ascending=false&limit=100

# markets expiring in the next 48h
?closed=false&active=true
  &end_date_min=<today-iso>&end_date_max=<today+2d-iso>
  &order=volume24hr&ascending=false&limit=100

# title search
?closed=false&active=true&title=Bitcoin+above
  &order=endDate&ascending=true&limit=10
```

### Response shape (event)

```json
{
  "id": "16167",
  "ticker": "…",
  "slug": "…",
  "title": "…",
  "endDate": "2026-04-18T16:00:00Z",
  "active": true,
  "closed": false,
  "restricted": false,
  "negRisk": false,
  "liquidity": 162312.0,
  "volume": 29796377.78,
  "openInterest": 2181689.99,
  "volume24hr": 555405.48,
  "competitive": 0.997,
  "markets": [ /* child markets — see next */ ]
}
```

### Response shape (market)

```json
{
  "id": "516926",
  "conditionId": "0x19ee…",
  "questionId": "0x…",
  "slug": "…",
  "endDate": "2025-12-31T12:00:00Z",
  "outcomes":       "[\"Yes\", \"No\"]",     // JSON-encoded string
  "outcomePrices":  "[\"0.87\", \"0.13\"]",  // JSON-encoded string
  "clobTokenIds":   "[\"<77-digit>\", \"<77-digit>\"]", // JSON-encoded string
  "orderMinSize":   "5",        // SHARES, not dollars
  "active": true,
  "closed": false,
  "gameStartTime": null
}
```

**Critical:** `outcomes`, `outcomePrices`, and `clobTokenIds` are
JSON-encoded **strings**, not arrays — `json.loads()` before indexing.
Index 0 = YES, index 1 = NO. `restricted: true` is a UI display flag, not
a trading block.

---

## 2. CLOB API — Order Book + Trading

Writes (`/order`, `/orders/*`) need L2 auth. Reads are public.

### Auth endpoints (L1)

| Method | Path | Note |
|---|---|---|
| POST | `/auth/api-key` | Create new credentials |
| GET  | `/auth/derive-api-key` | Recover existing credentials |

Both require the L1 EIP-712 header set:
`POLY_ADDRESS`, `POLY_SIGNATURE`, `POLY_TIMESTAMP`, `POLY_NONCE`.

### Market data (public)

| Method | Path | Returns |
|---|---|---|
| GET | `/book?token_id=…` | Bids + asks + tick + min_size + last trade + `neg_risk` |
| GET | `/books?token_ids=…` | Batched books (comma-list of token_ids) |
| GET | `/price?token_id=…&side=buy|sell` | Best bid or ask |
| GET | `/midpoint?token_id=…` | Bid-ask midpoint |
| GET | `/tick-size?token_id=…` | Minimum price increment |
| GET | `/fee-rate/{token_id}` | `base_fee` in **basis points** |
| GET | `/clob-markets/{condition_id}` | Tokens, tick, fees, rewards, RFQ, delay flags |
| GET | `/markets/{market_id}/clob_info` | Full CLOB-side config dump |
| GET | `/prices-history?market={token_id}&interval=1h&fidelity=60` | OHLC time series |
| POST | `/batch-prices-history` | Up to 20 markets in one call |

#### `/book` response

```json
{
  "market": "0x…<condition_id>",
  "asset_id": "<77-digit token_id>",
  "timestamp": "1234567890",
  "hash": "a1b2…",
  "bids": [{ "price": "0.45", "size": "100" }, …],
  "asks": [{ "price": "0.46", "size": "150" }, …],
  "min_order_size": "1",
  "tick_size": "0.01",
  "neg_risk": false,
  "last_trade_price": "0.45"
}
```

#### `/prices-history` parameters

| Param | Type | Notes |
|---|---|---|
| `market` | string (required) | The **token_id** (asset_id), not condition_id |
| `startTs`, `endTs` | unix seconds | Optional range filter |
| `interval` | enum | `max`, `all`, `1m`, `1w`, `1d`, `6h`, `1h` |
| `fidelity` | integer (minutes) | Default 1 |

Response: `{"history": [{"t": <unix>, "p": <float>}, …]}`.

### Trading (L2 required)

| Method | Path | Use |
|---|---|---|
| POST | `/order` | Submit a signed order (GTC, GTD, FOK, FAK) |
| GET  | `/orders` | Open orders for the authenticated address |
| GET  | `/order/{id}` | Single order status |
| DELETE | `/orders/{id}` | Cancel one |
| DELETE | `/orders` | Cancel many |
| GET  | `/trades` | Trade history |

### Rewards / rebates

| Method | Path | Use |
|---|---|---|
| GET | `/rewards/markets/multi` | Markets with active reward configs (paginated) |
| GET | `/markets/{market_slug}/rewards` | Raw rewards config for a market |
| GET | `/rebates/current?date=YYYY-MM-DD&maker_address=0x…` | Maker rebate accrual |

---

## 3. Data API — Analytics

Read-only, public. Aggregated views across users, markets, and time.

| Method | Path | Use |
|---|---|---|
| GET | `/positions?user={address}` | Open positions for a wallet |
| GET | `/trades?user={address}` | Trade history |
| GET | `/activity?limit=100` | Cross-market recent activity |
| GET | `/holders/{token_id}` | Token holders + balances |
| GET | `/value?user={address}` | Account value snapshot |
| GET | `/pnl/user?user={address}` | PnL summary |

Most endpoints accept `limit` + cursor pagination.

---

## 4. Relayer — Gasless Transaction Submission

Builder API keys (HMAC) or Relayer API keys are accepted.

| Method | Path | Use |
|---|---|---|
| POST | `/submit` | Submit a gasless transaction |
| GET  | `/transaction/{id}` | Poll status by transactionID |

Submission returns immediately with `transactionID` and `state: STATE_NEW`;
poll for `state: STATE_MINED` and the resulting tx hash.

### Auth header sets

**Builder API key:**
```
BUILDER_API_KEY
BUILDER_API_KEY_PASSPHRASE
BUILDER_API_KEY_TIMESTAMP
BUILDER_API_KEY_SIGNATURE   ← HMAC-SHA256 of (timestamp + method + path + body)
```

**Relayer API key** (created via Gamma auth, max 100 per address):
```
RELAYER_API_KEY
RELAYER_API_KEY_ADDRESS     ← must match the wallet that owns the key
```

The `/submit` request body carries a `proxyWallet` field — the user's
Polymarket proxy wallet address that ultimately holds collateral and tokens.

---

## Rate Limits (per IP / per key)

| Group | General | Hot endpoints |
|---|---|---|
| Gamma — `/events`, `/markets` | 4000 / 10s | 200–500 / 10s |
| Data — positions/trades/value | 1000 / 10s | 150–200 / 10s |
| CLOB — market data | 9000 / 10s | 1500 / 10s (`/book`, `/price`, `/midpoint`); 500 / 10s for batched `/books`, `/prices`, `/midpoints`; 1000 / 10s `/prices-history`; 200 / 10s `/tick-size` |
| CLOB — `POST /order` | 5000 / 10s burst | 48000 / 10min sustained |
| CLOB — `/auth/*` | 100 / 10s | — |

Hot CLOB endpoints have burst + sustained windows. Always backoff on 429.

---

## ID Quick-Reference

| ID | Format | Where used |
|---|---|---|
| `token_id` (asset_id) | 77-digit decimal string | CLOB `/book`, `/price`, `/prices-history` (`market=` param), order submission |
| `condition_id` | `0x…` 32-byte hex | CTF contracts, Data API, `/clob-markets/{condition_id}` |
| `question_id` | `0x…` hex | UMA resolution |
| `slug` | kebab-case | Gamma `/markets?slug=`, URLs |
| `event_id` | numeric string | Gamma `/events/{id}` |

`/prices-history` takes `market=<token_id>` — confusing because the param is
named "market" but expects a token (asset) ID, not a condition_id.

---

## Pagination

CLOB list endpoints use cursor pagination:
- Request: `next_cursor=<value>&page_size=<n>`
- Response: `{ data: [...], next_cursor: "<next>" or "LTE=" }`
- `next_cursor: "LTE="` indicates the last page.

Gamma list endpoints use `limit` + `offset` (or `order` + `ascending`).

---

## Authoritative sources

- Concept pages: `docs.polymarket.com/concepts/{markets-events,positions-tokens,prices-orderbook,order-lifecycle,resolution,pusd}.md`
- API ref: `docs.polymarket.com/api-reference/*` (rate limits at `/api-reference/rate-limits.md`, error codes at `/resources/error-codes.md`)
- Docs index for crawlers: `docs.polymarket.com/llms.txt`
- Official clients (Context7 IDs): `/polymarket/clob-client` (TS),
  `/polymarket/rs-clob-client-v2` (Rust), `/polymarket/polymarket-cli` (CLI),
  `/pawsengineer/polymarket-rs` (community Rust).
