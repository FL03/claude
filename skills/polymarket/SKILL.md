---
name: polymarket
description: |
  Polymarket exchange reference for prediction-market trading on Polygon. Covers
  protocol architecture (CLOB / relayer / on-chain CTF), authentication tiers
  (L1 EIP-712 vs L2 HMAC API keys), pUSD collateral, market types (binary,
  multi-outcome neg-risk, sports, crypto strikes), UMA resolution, fee structure,
  and ID disambiguation (token_id vs condition_id vs question_id vs slug).
  Companion files: `apis.md` (Gamma / CLOB / Data / Relayer endpoint reference —
  base URLs, request/response shapes, rate limits, Context7-grounded against
  docs.polymarket.com), `strategies.md` (trading playbooks per market category),
  `exploits.md` (structural edge ledger). Exchange-specific companion to @trader.
user-invocable: true
version: 5.1.0
metadata:
  openclaw:
    emoji: "🔮"
---

# POLYMARKET — Exchange Architecture & Reference

Polymarket is a binary prediction-market exchange on Polygon (chainId 137). Each
market issues two ERC-1155 outcome tokens via the Gnosis Conditional Token
Framework (CTF); the winning side redeems for $1.00 of collateral, the losing
side for $0.00. Collateral is **pUSD** — an on-chain wrapper around USDC.e
managed by the `CollateralOnramp` / `CollateralOfframp` contracts; users
deposit USDC.e, trade in pUSD, withdraw back to USDC.e.

This SKILL.md is the primer. Endpoint depth lives in `apis.md`; strategy
playbooks in `strategies.md`; live edge ledger in `exploits.md`.

---

## Protocol Architecture

```
User wallet (EOA) ──signs EIP-712──► CLOB API (off-chain matching)
                                          │
                            matched orders submitted by
                                          ▼
                            Relayer (relayer-v2.polymarket.com)
                                          │
                                  gasless tx broadcast
                                          ▼
                            Polygon (CTF Exchange contract)
                                          │
                            ┌─────────────┴─────────────┐
                            │ ERC-1155 outcome tokens   │
                            │ pUSD collateral movement  │
                            └─────────────┬─────────────┘
                                          ▼
                                   UMA Optimistic Oracle
                                   (resolution + dispute)
```

| Layer | Responsibility | On-chain? |
|---|---|---|
| CLOB | Off-chain order book, matching, signing checks, rate limiting | No |
| Relayer | Gasless tx submission, nonce mgmt, proxy-wallet broadcasting | Bridge |
| Polygon CTF | Settlement, collateral locking, token transfer | Yes |
| UMA OO | Outcome proposal + 2h dispute window | Yes |

Users do not pay Polygon gas directly — the relayer absorbs it. Withdrawals
through the standard USDC.e bridge are user-gas.

---

## Authentication: L1 vs L2

| Tier | Signs with | Used for | Headers |
|---|---|---|---|
| **L1** | EOA private key, EIP-712 | Credential creation, deposits/withdrawals | `POLY_ADDRESS`, `POLY_SIGNATURE`, `POLY_TIMESTAMP`, `POLY_NONCE` |
| **L2** | Derived API key + secret, HMAC-SHA256 | All trading endpoints | `POLY_ADDRESS`, `POLY_SIGNATURE`, `POLY_TIMESTAMP`, `POLY_API_KEY`, `POLY_PASSPHRASE` |

### L2 credential derivation

A one-time L1 EIP-712 signature over the `ClobAuthDomain` (v1, chainId 137)
yields three values:

```
apiKey      uuid       — non-secret identifier
secret      base64     — HMAC-SHA256 key for L2 request signing
passphrase  string     — required alongside the signature on every L2 request
```

In the official client (Python `py_clob_client_v2`, TypeScript
`@polymarket/clob-client-v2`, Rust `polymarket-rs`):

```python
credentials = client.create_or_derive_api_key()
# {apiKey, secret, passphrase}
```

Without the SDK, derive manually: POST `/auth/api-key` (creates) or GET
`/auth/derive-api-key` (re-derives) with L1 headers. Programmatic agents
(`axiom__*` tools, custom bots) always use L2 — no per-trade on-chain
signature, no MetaMask popups.

---

## Market Structure

### Event vs market

- **Event** — a container that groups one or more related markets (e.g., a
  presidential election event containing one market per candidate). A
  single-market event is operationally equivalent to its sole market.
- **Market** — one binary YES/NO question. Issues two outcome tokens.

### Identifier ladder

| ID | Format | Used by | Notes |
|---|---|---|---|
| `token_id` | decimal string (~77 digits) | CLOB `/book`, `/price`, order placement, `axiom__*` | ERC-1155 token ID for one outcome. Two per market (YES + NO). |
| `condition_id` | `0x…` 32-byte hex | CTF contracts, Data API, `/clob-markets/{condition_id}` | Identifies the market's on-chain condition. |
| `question_id` | `0x…` hex | UMA resolution | Hash used during oracle proposal. |
| `slug` | kebab-case string | Gamma API, URLs | Human-readable (e.g. `bitcoin-above-95000-april-18`). |
| `event_id` | numeric string | Gamma `/events` | Parent event identifier. |

`axiom_buy(token_id=…)` needs the 77-digit token_id, not the slug. The
Gamma `clobTokenIds` field is **a JSON-encoded string**, not a JSON array —
`json.loads(market["clobTokenIds"])` to unwrap. Index 0 = YES, index 1 = NO.
Same caveat applies to `outcomePrices` and `outcomes`.

### Market types

- **Binary YES/NO** — the fundamental shape. Every market is this under the hood.
- **Negative-risk multi-outcome** — multiple binary markets under one event
  with the `negRisk: true` flag (and a corresponding `neg_risk` field on
  `/book`). Outcomes are mutually exclusive; YES prices across all child
  markets should sum to ~$1.00. Sums below $1.00 are structural arbitrage —
  bots usually catch them in seconds.
- **Crypto strike series** — "BTC above $X on [date]?" daily markets, 11
  strikes per asset per day, resolved against the **Chainlink BTC/USD feed
  on Polygon at the market endDate** (typically 16:00 UTC). Not spot, not
  CEX — Chainlink is THE oracle.
- **Crypto sprints (5m / 15m up/down)** — slug pattern
  `{asset}-updown-{5m|15m}-{unix_epoch}` where epoch = `ceil(now / interval) * interval`.
  Assets: btc, eth, sol, xrp, doge, bnb, hype. Roughly 50/50 absent directional signal.
- **Sports** — moneyline / spread / over-under / player props. Orders auto-
  cancel at `gameStartTime` on GTC; a **1-second matching delay** is applied
  to sports trades per the order-lifecycle docs. ESPN API is the standard
  live-score feed.

Endpoint depth, response shapes, and pagination are in `apis.md`.

---

## Order Lifecycle

Five stages: **create → submit → match-or-rest → settle → confirm**.

```
1. Client builds order, signs EIP-712 with L2 secret
2. POST /order to CLOB — operator validates sig, balance, allowance, tick size
3. If marketable (buy ≥ best ask / sell ≤ best bid) → matched immediately
   Else → rests on the book until filled, cancelled, or expired
4. CTF Exchange contract atomically swaps tokens + pUSD on Polygon
5. Trade finalized; available in /trades and /positions
```

Order types (all signed off-chain, all dispatched through CLOB):

| Type | Behavior |
|---|---|
| GTC | Good-till-cancelled — rests until filled or cancelled |
| GTD | Good-till-date — rests until filled, cancelled, or expires |
| FOK | Fill-or-kill — must fill in full or cancel entirely |
| FAK | Fill-and-kill — partial fill OK, residual cancelled |
| `post_only` | Modifier — rejects if order would immediately cross the spread |

`tick_size` and `min_order_size` are per-market (returned by `/book` and
`/clob-markets/{condition_id}`). Common values: tick 0.01, min size 5 shares.

---

## Fees & Rewards

Fees are per-market and fetched live via CLOB; do not hard-code rates.
Authoritative endpoints: `GET /fee-rate/{token_id}` (base fee in basis points)
and `GET /clob-markets/{condition_id}` (full fee + rewards config). Sample
shape from the docs:

```json
{ "base_fees": { "maker": "0.001", "taker": "0.002" },
  "rewards":   { "maker_rebate": "0.0005" } }
```

Typical observed base fees are in the 10–30 bps range. A maker-rebate program
runs on a per-market reward schedule; see `GET /rewards/markets/multi` and
`GET /rebates/current` for live config.

Settlement gas is absorbed by the relayer. Withdrawals over the USDC.e bridge
are user-gas on Polygon.

### Net-edge rule

```
required_edge > taker_fee / (1 - entry_price)

entry = 0.65, taker = 0.20%   →  need >0.6%
entry = 0.90, taker = 0.20%   →  need >2.0%
entry = 0.65, taker = 2.00%   →  need >5.7%   (only if fees turn out high)
entry = 0.90, taker = 2.00%   →  need >20%
```

Always query live fees before sizing — using a stale 2% assumption blows up
sizing on tight-spread markets where the actual fee is closer to 0.2%.

---

## Resolution (UMA Optimistic Oracle)

```
1. Market endDate passes — the question is now resolvable
2. Anyone posts a proposal (YES or NO) with a 750 pUSD bond
3. 2-hour challenge window opens
4a. No dispute → market resolves; proposer gets bond + reward back
4b. Dispute → counter-bond posted; new proposal round
4c. Second dispute → escalates to UMA DVM (token holder vote, ~48h)
5. Winning side redeems each share for $1.00 of pUSD
```

Total disputed timeline: 4–6 days. Clean (undisputed) timeline: ≈2 hours.

The 2-hour challenge window is the most exploitable structural feature —
when an outcome is verifiable but the market still trades because UMA hasn't
finalized, YES typically prices at $0.92–$0.98. See `exploits.md` §IV.

---

## Rate Limits (top-line)

| API | General | Hot endpoints | Notes |
|---|---|---|---|
| Gamma | 4000 / 10s | 200–500 / 10s | All read-only, no auth |
| Data  | 1000 / 10s | 150–200 / 10s | Read-only, no auth |
| CLOB  | 9000 / 10s | 1500 / 10s on `/book`, `/price` | Auth endpoints (`/order` etc.) lower |
| CLOB auth-mgmt (`/auth/*`) | 100 / 10s | — | Per-address |

Full per-endpoint matrix in `apis.md`.

---

## Companion Files & Cross-Skill Notes

Progressive disclosure — load only what the task needs.

- **`apis.md`** — Gamma / CLOB / Data / Relayer endpoint reference. Base URLs,
  request/response schemas, query-parameter inventory, pagination, rate
  limits per endpoint group. Context7-grounded against
  `docs.polymarket.com/api-reference/*`.
- **`strategies.md`** — discovery → verification → gate-check → execute
  playbooks per market category (BTC strikes, sports, news, resolution
  snipe, neg-risk arb).
- **`exploits.md`** — living ledger of structural edges (Chainlink oracle lag,
  UMA window, weather forecast lead, CEX-PM lag, neg-risk arb). Each entry
  carries reliability rating and decay status.

### Cross-skill

- **`@trader`** — generalized agent protocol + 9-gate contract. Load
  alongside this skill for autonomous execution: `trader/SKILL.md` (protocol),
  `trader/jailbreak.md` (autonomy grant), `trader/axiom.md` (Axiom MCP tool
  surface). The trader skill calls into `polymarket/strategies.md` during the
  DISCOVER phase and into this SKILL.md whenever it needs to reason about
  market mechanics.
- **`@finance`** — Kelly sizing, risk metrics, probability modelling. Use
  when computing `p_true` estimates or position sizing.

### Authoritative external references

- `https://docs.polymarket.com/` — canonical docs (index at `/llms.txt`).
- `https://docs.polymarket.com/concepts/{markets-events,positions-tokens,prices-orderbook,order-lifecycle,resolution,pusd}.md` — core concepts.
- `https://docs.polymarket.com/api-reference/` — full endpoint reference.
- `/pawsengineer/polymarket-rs`, `/polymarket/rs-clob-client-v2`,
  `/polymarket/clob-client`, `/polymarket/polymarket-cli` — official + community
  client libraries (Context7-indexed).
