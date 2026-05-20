---
name: polymarket
description: |
  Polymarket exchange reference. Protocol mechanics, CLOB/Gamma/Data APIs, L1 vs L2
  authentication, relayer architecture, market types, resolution, fees, and structural
  overview. Exchange-specific companion to @trader.
user-invocable: true
metadata:
  openclaw:
    emoji: "🔮"
---

# POLYMARKET — Exchange Architecture & Reference

Polymarket is a binary prediction market exchange built on Polygon (Ethereum L2).
Markets resolve to $1.00 (YES) or $0.00 (NO). All collateral is USDC.e.

---

## Protocol Architecture

```
User → CLOB API (off-chain order book) → Relayer → Polygon (on-chain settlement)
                        ↑
              Gamma API (market discovery)
              Data API  (historical data)
```

### Layers
| Layer | Purpose | On-chain? |
|-------|---------|-----------|
| CLOB | Central Limit Order Book — order matching | No (off-chain) |
| Relayer | Submits matched orders to chain; handles gas | Bridging layer |
| Polygon | Settlement, collateral, resolution | Yes |
| UMA Oracle | Resolution verification + dispute | Yes |

Orders are matched off-chain at near-zero latency. Settlement happens on Polygon,
but you don't interact with it directly — the relayer handles gas.

---

## Authentication: L1 vs L2

### L1 Authentication (Direct Wallet)
- Signs with an Ethereum EOA (externally owned account) — e.g., MetaMask
- Used by the Polymarket web UI
- Signs EIP-712 typed data for each order
- Requires on-chain allowance approval for USDC.e transfers

### L2 Authentication (API Keys — what Axiom uses)
- Derived keypair from a master EOA signature (one-time setup)
- API Key + Secret + Passphrase stored server-side on the Axiom node
- Signs orders locally; Axiom node handles relaying
- Does NOT require per-trade on-chain transactions
- **This is the programmatic path.** All `axiom__` tool calls use L2 auth.

### Key Derivation (reference only)
```
Master signature (from L1 EOA) → HMAC-SHA256 → L2 keypair
L2 private key signs order payloads → submitted to CLOB API
```

Axiom pre-handles all of this. You never touch raw keys in tool calls.

---

## APIs

### 1. Gamma API — Market Discovery (no auth required)
Base: `https://gamma-api.polymarket.com`

```
GET /events
  ?closed=false&active=true
  &order=volume24hr&ascending=false&limit=100
  → All active markets sorted by volume

GET /events
  ?closed=false&active=true
  &end_date_min=TODAY&end_date_max=TOMORROW_PLUS_1
  &order=volume24hr&ascending=false&limit=100
  → Markets expiring in next 48 hours

GET /events
  ?closed=false&active=true
  &title=Bitcoin+above
  &order=endDate&ascending=true&limit=10
  → BTC daily strikes, earliest first

GET /markets?slug={slug}&limit=1
  → Full market details by URL slug
```

**Key response fields:**
```json
{
  "title": "Bitcoin above $95,000 on April 18?",
  "slug": "bitcoin-above-95000-april-18",
  "endDate": "2026-04-18T16:00:00Z",
  "volume": "42381.50",
  "liquidity": "8920.00",
  "outcomePrices": "[\"0.87\", \"0.13\"]",      ← JSON STRING, must parse
  "clobTokenIds": "[\"<77digit>\", \"<77digit>\"]",  ← JSON STRING, must parse
  "orderMinSize": "5",                             ← in SHARES, not dollars
  "restricted": false,                              ← UI flag only, ignore for trading
  "gameStartTime": null                             ← if not null and in past, game is live
}
```

**CRITICAL: `outcomePrices` and `clobTokenIds` are JSON strings.** Always `json.loads()` them.
Index 0 = YES, Index 1 = NO.

### 2. CLOB API — Order Execution (L2 auth required)
Base: `https://clob.polymarket.com`

You do not call this directly — all calls route through `axiom__` tools.

Endpoints for reference:
```
POST /order              → submit order (FAK or GTC)
GET  /book?token_id=X    → order book for token
GET  /orders?market=X    → open orders for market
DELETE /orders/{id}      → cancel order
GET  /positions          → open positions (by wallet)
```

### 3. Data API — Historical Data
Base: `https://data-api.polymarket.com`

```
GET /prices-history?market={condition_id}&interval=1h&fidelity=60
  → OHLCV price history for a market

GET /activity?limit=100
  → Recent trade activity across all markets
```

Use for: backtesting, identifying vol patterns, finding historically mispriced markets.

---

## Market Types

### Daily Crypto Strikes
- Format: "Bitcoin above $X on [date]?"
- 11 strike prices per asset per day
- Resolution: **4:00 PM UTC** via Chainlink oracle (BTC/USD feed)
- Chainlink is THE oracle — not spot price, not CEX price
- If Chainlink > strike → YES resolves $1.00; NO resolves $0.00

### Crypto Sprints (5m / 15m Up/Down)
- New market every 5 or 15 minutes, 24/7
- Slug format: `{asset}-updown-{5m|15m}-{unix_epoch}` where epoch = ceil(now/interval)*interval
- Assets: btc, eth, sol, xrp, doge, bnb, hype
- Resolution: price at end of interval vs. price at start
- **These are ~50/50 without directional momentum data.**

### Sports
- Moneyline (who wins), spread, over/under, player props
- **3-second matching delay** on all sports markets (anti-sniping measure)
- Orders auto-cancel at `gameStartTime` if GTC
- Live score data: ESPN API

### Negative Risk Events
- Multi-outcome markets: "Who wins the championship?"
- One outcome pays $1.00; all others pay $0.00
- YES prices across all outcomes should sum to ~$1.00
- If sum < $1.00 → structural arbitrage opportunity (buy all, guaranteed profit)

---

## Resolution Process

```
1. Market expires at endDate
2. UMA proposer submits resolution (YES or NO)
3. 2-hour challenge window begins
4. If no dispute → resolves automatically
5. If disputed → UMA token holders vote
6. Winners auto-credited USDC.e; NO tokens go to $0.00
```

**Resolution sniping:** If outcome is known but market is still open (within 2h window),
YES can be bought at $0.92–0.98 and will settle at $1.00. 2–8% return in hours.

---

## Fees & Costs

```
Taker fee:       ~2% of order value (deducted from winnings)
Maker rebate:    ~0.1% (for GTC orders that provide liquidity)
Holding reward:  ~4% annualized on open positions (auto-accrued)
Gas fees:        Zero to user (relayer absorbs gas costs)
Withdrawal:      Standard Polygon USDC.e bridge (user pays gas)
```

**Net edge requirement after fees:**
```
Required EV > taker_fee / (1 - entry_price)

At entry = 0.65:  need EV > 2% / 0.35 ≈ 5.7%
At entry = 0.90:  need EV > 2% / 0.10 = 20%

High-price entries require much larger edges to be profitable.
```

---

## ID Types

```
token_id      → 77-digit decimal number. Used by CLOB and axiom__ tools. One per outcome.
condition_id  → 0x... hex string. Used by Data API and on-chain.
slug          → human-readable URL segment (e.g., "bitcoin-above-95000-april-18")
event_id      → numeric Gamma ID for the parent event (groups multiple markets)
```

Never mix these up. `axiom_buy(token_id=...)` needs the 77-digit number, not the slug.
