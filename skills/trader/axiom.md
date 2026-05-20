---
name: trader:axiom
description: |
  Axiom MCP platform reference. Full tool API for the Toronto trading node: buy, sell,
  stop-loss, redeem, positions, balance, pending, order book, market info, and Chainlink oracle.
  All tool calls route through axiom__ namespace.
type: reference
---

# AXIOM — MCP Trading Platform Reference

All execution routes through the **Axiom node (Toronto)**. Zero geographic restrictions.
All tools are in the `axiom__` namespace via MCP.

---

## Tool Reference

### Account State

```
axiom__axiom_balance()
  → USDC.e balance available for trading
  → Always call first in every cycle
  → available = balance − $5.00 floor

axiom__axiom_positions()
  → All open positions with: market title, token_id, size (shares), entry_price, current_price, P&L
  → Call before every trade to check correlation (Gate 5) and drawdown state (Gate 6)

axiom__axiom_pending()
  → Pending limit orders (GTC orders resting on book)
  → Check to avoid doubling up on partially filled positions

axiom__axiom_trades()
  → Recent trade history
  → Use for drawdown tracking and session P&L calculation
```

### Execution

```
axiom__axiom_buy(token_id, price, amount)
  → token_id: 77-digit YES or NO token ID (from clobTokenIds[0] or [1])
  → price: limit price in USDC.e (0.01–0.99)
  → amount: USDC.e to spend (NOT shares — Axiom handles the conversion)
  → Returns: order confirmation or error

axiom__axiom_sell(token_id, price, size)
  → token_id: the token you hold (from positions)
  → price: limit price to sell at
  → size: number of SHARES to sell (not dollars)
  → Use to exit a position or lock in profits

axiom__axiom_cancel(order_id)
  → Cancel a pending GTC order
  → order_id from axiom__axiom_pending() results

axiom__axiom_stop_loss(token_id, stop_price, size)
  → Automatically sells size shares when bid price drops to stop_price
  → Set immediately after buying a position
  → stop_price = entry_price × 0.5 is a reasonable default (50% loss trigger)

axiom__axiom_redeem()
  → Claims all resolved winning positions
  → Run at the start of each cycle — unclaimed winnings reduce apparent balance
```

### Market Data

```
axiom__market_search(query)
  → Full-text search across active Polymarket markets
  → Returns: title, slug, token_ids, outcome_prices, volume, end_date
  → Use for targeted discovery: "Bitcoin above 90000", "Lakers vs Warriors"

axiom__market_info(slug)
  → Full market details by URL slug
  → Returns: description, resolution criteria, outcome_prices, clobTokenIds, orderMinSize, restricted

axiom__market_book(token_id)
  → Live CLOB order book for a specific token
  → Returns: bids (price, size), asks (price, size)
  → Check before executing: ensure sufficient ask depth at your target price (Gate 8)
  → Best ask = asks[0][0]; total liquidity at target = sum of ask sizes ≤ target_price
```

### Oracle

```
axiom__chainlink_btc_price()
  → Current BTC price from Chainlink oracle
  → THIS IS THE ORACLE POLYMARKET USES for BTC strike settlement
  → If Chainlink price > strike and YES < $0.95 → verified edge
  → Updates approximately every 60 seconds or on 0.5% deviation
```

---

## Sizing Formula

```python
# Given:
balance       = axiom_balance()
available     = balance - 5.00           # $5 floor
entry_price   = float(asks[0][0])        # best ask from order book
p_true        = your_estimate            # Bayesian posterior

# Kelly calculation:
b       = (1 - entry_price) / entry_price
f_star  = (b * p_true - (1 - p_true)) / b   # full Kelly = p_true - entry_price
f_half  = f_star / 2                          # always half Kelly

# Final size:
kelly_amount  = f_half * available
size          = min(kelly_amount, 3.50, available)

# Gate checks:
if size < 1.00:   raise GateFail("SIZING: edge too thin — half-Kelly < $1 minimum")
if f_star < 0:    raise GateFail("SIZING: negative Kelly — you're on wrong side")
```

---

## Token ID Handling

Polymarket's Gamma API returns token IDs as **JSON strings inside JSON**:
```json
"clobTokenIds": "[\"77777...YES_TOKEN\", \"88888...NO_TOKEN\"]"
"outcomePrices": "[\"0.65\", \"0.35\"]"
```

**Always parse twice:**
```python
import json
token_ids = json.loads(market["clobTokenIds"])   # ["YES_token_id", "NO_token_id"]
prices    = json.loads(market["outcomePrices"])   # ["0.65", "0.35"]

yes_token = token_ids[0]   # 77-digit number string
no_token  = token_ids[1]

yes_price = float(prices[0])   # 0.65
no_price  = float(prices[1])   # 0.35 = 1 - yes_price (always)
```

**Note:** `orderMinSize` is in **shares** not dollars. Min cost = orderMinSize × price.

---

## Order Types

| Type | Description | Min Size | Use When |
|------|-------------|----------|----------|
| FAK (Fill-And-Kill) | Fill what's available, cancel rest | $1 USDC | Taker — want immediate fill |
| GTC (Good-Till-Cancelled) | Rest on book until filled or cancelled | 5 shares | Maker — want better price |

**Axiom default:** FAK (taker). For sniper trades, use FAK at best ask.
For pre-game sports where you can wait, use GTC 1-2¢ below ask.

---

## Error Handling

| Error | Likely Cause | Action |
|-------|-------------|--------|
| `insufficient_funds` | Balance < amount | Reduce size or skip |
| `market_closed` | Past end_date | Skip market |
| `order_below_minimum` | size < orderMinSize | Skip — edge too thin |
| `token_not_found` | Wrong token_id | Re-fetch market_info |
| `price_out_of_range` | price outside [0.01, 0.99] | Check entry calculation |

On any error: log → skip this market → continue cycle. Never retry a failed execution
with modified parameters without re-running the full gate check.

---

## Axiom Node Details

- **Location:** Toronto, Canada
- **Protocol:** All Polymarket CLOB API calls proxied through node
- **Authentication:** Pre-configured (no auth needed in tool calls)
- **Rate limits:** None observed; call freely
- **Settlement:** USDC.e on Polygon (chain 137) — no action required
- **Latency:** Sub-second for order submission
