---
name: trader:axiom
description: |
  Axiom MCP platform reference. Full tool surface for the Toronto trading node:
  account state (balance/positions/pending/trades/status), execution (buy/sell/
  stop_loss/cancel/cancel_orders/redeem/redeem_slug), market data (search/info/
  book/midpoint/price/candles), Chainlink oracle, scanner (scan/watchlist), and
  kill-switch safety surface. All tool IDs are `mcp__axiom__<tool>` when invoked
  from Claude Code (server name = "axiom" in .mcp.json).
type: reference
---

# AXIOM — MCP Trading Platform Reference

All execution routes through the **Axiom node (Toronto)**. Zero geographic restrictions —
the node is the operator's pre-authenticated relay; tool calls inherit its L2 credentials.

**Claude Code tool naming.** The MCP server is registered as `axiom` in `.mcp.json`.
The Claude Code harness exposes each server tool as `mcp__axiom__<tool_name>`. Throughout
this reference the `mcp__axiom__` prefix is omitted for brevity — `axiom_buy(...)` in this
doc means `mcp__axiom__axiom_buy(...)` at the tool-call site.

The underlying Rust MCP server is at `~/src/fl03/axiom/bin/mcp/` (binary: `axiom-mcp`).
The equivalent CLI shim is `~/src/fl03/axiom/bin/axiom-cli.sh` — argument order matches
the MCP tools 1:1 and is the fallback when MCP is unavailable.

---

## Tool Reference

### Account State

```
axiom_balance()
  → USDC.e balance available for trading (full balance, not net of floor)
  → Always call first in every cycle
  → available = balance − $5.00 floor

axiom_positions()
  → All open positions: market_title, token_id, side, size (shares), entry_price,
    current_price, unrealized_pnl
  → Call before every trade — feeds Gate 5 (CORRELATION) and Gate 6 (DRAWDOWN)

axiom_pending()
  → Pending GTC orders resting on the book (order_id, token_id, price, size, side)
  → Check to avoid doubling up on partially filled positions
  → order_id values feed axiom_cancel()

axiom_trades()
  → Recent trade history with realized P&L
  → Use to compute current consecutive-loss streak and session P&L

axiom_status()
  → Node liveness + kill-switch level + connection health
  → Call once at session start; abort if status is not "online" + "normal"
```

### Execution

```
axiom_buy(token_id, side, price, amount)
  → token_id: 77-digit CLOB token ID from clobTokenIds[0] (YES) or [1] (NO)
  → side:     "yes" | "no" — MUST match token_id index (sanity guard; mismatch = reject)
  → price:    limit price in USDC.e, 0.01–0.99 inclusive
  → amount:   USDC.e to SPEND (NOT shares — node converts to shares at fill)
  → Returns:  {status, order_id, filled_size, avg_price} or error
  → Default order type: FAK (Fill-And-Kill). Use price ≥ best_ask for taker fill.

axiom_sell(token_id, price, size)
  → token_id: the YES or NO token you currently hold
  → price:    limit price to sell at, 0.01–0.99
  → size:     number of SHARES to sell (NOT dollars)
  → Used to exit, lock in profit, or scale down

axiom_stop_loss(token_id, stop_price, size, market_slug?, ttl_secs?)
  → Resting stop order — auto-sells `size` shares when bid drops to `stop_price`
  → Set immediately after every buy that exits at < $0.95
  → Reasonable default: stop_price = entry_price × 0.5 (50% loss trigger)
  → ttl_secs: lifetime of the stop order on the node; defaults to a long horizon

axiom_cancel(order_id)
  → Cancel a single pending GTC order by ID
  → order_id values come from axiom_pending()

axiom_cancel_orders()
  → Bulk cancel ALL resting orders on the node (admin path)
  → Use during emergency unwind or when thesis flips wholesale

axiom_redeem()
  → Claim ALL resolved winning positions in one call
  → Run at the START of every cycle — unclaimed winnings depress apparent balance
  → Idempotent: safe to call when nothing is redeemable

axiom_redeem_slug(slug)
  → Redeem a single market by Polymarket slug
  → Use when one position resolved but others are still pending
```

### Market Data

```
market_search(query)
  → Full-text search across active Polymarket markets
  → Returns: title, slug, token_ids, outcome_prices, volume, end_date
  → Use for targeted discovery: "Bitcoin above 90000", "Lakers vs Warriors"

market_info(slug)
  → Full market details by URL slug
  → Returns: description, resolution criteria, outcome_prices, clobTokenIds,
    orderMinSize, restricted, gameStartTime, end_date

market_book(token_id)
  → Live CLOB order book for a single outcome token
  → Returns: bids [[price, size], ...], asks [[price, size], ...]
  → MUST be called immediately before every execution (Gate 8 LIQUIDITY)
  → Best ask = asks[0][0]; depth at target = Σ asks[i][1] where asks[i][0] ≤ target

market_midpoint(token_id)
  → Midpoint = (best_bid + best_ask) / 2 for a CLOB token
  → Cheaper than market_book when you only need a fair-value reference price

market_price(asset)
  → Spot price for an asset from the datasync service
  → Currently BTC only (datasync limitation) — empty asset defaults to "BTC"
  → NOT the settlement oracle — use chainlink_btc_price() for Gate 3 source

market_candles(asset, interval?, ...)
  → OHLCV candle history from datasync
  → Currently BTC only — for ETH/SOL/etc. use the exchange's public API directly
```

### Oracle

```
chainlink_btc_price()
  → Current BTC price from the Chainlink BTC/USD oracle on Polygon
  → THIS IS THE ORACLE POLYMARKET USES for BTC daily-strike settlement
  → Updates roughly every 60s OR on ≥ 0.5% deviation, whichever fires first
  → If Chainlink_price > strike AND YES < $0.95 → verified Gate 3 source for that strike
```

### Scanner / Watchlist

```
axiom_scan(pattern)
  → Run the node's market scanner. pattern: glob like "btc-*", "nba-*"; empty = all
  → Returns markets the scanner flagged as edge candidates
  → Faster than rolling your own discovery for known asset families

axiom_watchlist(action, pattern?, label?, category?)
  → action: "list" | "add" | "remove"
  → "list":   returns all watchlist entries
  → "add":    pattern + label required; category one of sports/crypto/weather/politics
  → "remove": pattern required
  → Persistent watchlist on the node; survives MCP restarts
```

### Kill Switch (Safety Surface)

```
kill_switch_get()
  → Returns current kill-switch level: "normal" | "reduced=<0-100>" |
    "no-new-orders" | "flatten"

kill_engage()
  → Engage emergency stop: flatten all positions, halt new orders
  → Use when: thesis catastrophically wrong, source feed compromised,
    or operator-issued panic

kill_disengage()
  → Restore "normal" level. Does NOT reset the circuit breaker — call
    node_cb_reset() separately if the breaker tripped.

kill_switch_set(level)
  → Fine-grained control: "normal", "reduced=50" (size cap %), "no-new-orders",
    "flatten" (emergency). Prefer kill_engage / kill_disengage for the common cases.
```

The trader agent does NOT auto-engage the kill switch as part of normal cycle flow.
It engages on hard stops (Drawdown Rule 3, session loss > 15%) and on Gate 3 source
failure (oracle stale or API unreachable).

---

## Sizing Formula

```python
# Given:
balance       = axiom_balance()
available     = balance - 5.00              # $5 floor
entry_price   = float(asks[0][0])           # best ask from market_book()
p_true        = your_posterior              # Bayesian estimate from Gate 3 source

# Kelly calculation (binary outcome, payoff = 1 unit if win, 0 if lose):
b       = (1 - entry_price) / entry_price
f_star  = (b * p_true - (1 - p_true)) / b   # simplifies to p_true - entry_price
f_half  = f_star / 2                         # always trade half-Kelly

# Final size:
kelly_amount  = f_half * available
size          = min(kelly_amount, 3.50, available)

# Gate 4 (SIZING) checks:
if f_star <= 0:   raise GateFail("SIZING: negative Kelly — wrong side of the trade")
if size  <  1.00: raise GateFail("SIZING: half-Kelly < $1 — edge too thin to justify slippage")
```

---

## Token ID Handling

Polymarket's Gamma API returns token IDs as **JSON strings nested inside JSON**:

```json
"clobTokenIds":   "[\"77777...YES_TOKEN\", \"88888...NO_TOKEN\"]"
"outcomePrices":  "[\"0.65\", \"0.35\"]"
```

**Always parse twice:**

```python
import json
token_ids = json.loads(market["clobTokenIds"])    # ["YES_token_id", "NO_token_id"]
prices    = json.loads(market["outcomePrices"])   # ["0.65", "0.35"]

yes_token = token_ids[0]    # 77-digit decimal string
no_token  = token_ids[1]

yes_price = float(prices[0])   # 0.65
no_price  = float(prices[1])   # 0.35 = 1 − yes_price (always true for binary markets)
```

`orderMinSize` is in **shares**, not dollars. Minimum cost in USDC.e = `orderMinSize × price`.

---

## Order Types

| Type | Description | Min Size | Use When |
|------|-------------|----------|----------|
| FAK (Fill-And-Kill) | Fill what's available, cancel rest | $1 USDC | Taker — want immediate fill |
| GTC (Good-Till-Cancelled) | Rest on book until filled or cancelled | 5 shares | Maker — want better price |

**Axiom default:** FAK (taker). For sniper trades, submit FAK at `best_ask` exactly.
For pre-game sports where you can wait, use GTC 1–2¢ below ask to capture the maker rebate.

---

## Error Handling

| Error | Likely Cause | Action |
|-------|-------------|--------|
| `insufficient_funds` | Balance < amount + floor | Reduce size or skip |
| `market_closed` | Past end_date | Skip market |
| `order_below_minimum` | size < orderMinSize | Skip — edge too thin to scale up |
| `token_not_found` | Wrong token_id, or market resolved | Re-fetch via market_info() |
| `price_out_of_range` | price outside [0.01, 0.99] | Recompute entry; check for resolution proximity |
| `kill_switch_active` | Node is in flatten or no-new-orders mode | Inspect kill_switch_get(); do not retry until normal |
| `AXIOM_API_KEY is not set` | Env not loaded in MCP launch | Operator action — restart MCP with .env loaded |

**Retry policy.** On transient errors (network, timeout): retry ONCE. On any
parameterized error: skip the market and re-run the full 9-gate contract on the
next candidate. Never retry a failed execution with modified parameters in the
same cycle — that's how slippage compounds.

---

## Axiom Node Details

- **Location:** Toronto, Canada
- **Protocol:** All Polymarket CLOB API calls proxied through the node
- **Authentication:** Pre-configured L2 keypair (no per-call auth needed in tool args)
- **Rate limits:** None observed at trader-cycle frequencies; call freely
- **Settlement:** USDC.e on Polygon (chain 137) — no user action required
- **Latency:** Sub-second for order submission; ~3s for Polymarket match confirmation
- **Source:** `~/src/fl03/axiom/bin/mcp/` (rust); image `jo3mccain/axiom-mcp:latest`
