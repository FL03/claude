---
name: polymarket:strategies
description: |
  Polymarket-specific trading strategy playbooks. Discovery, verification, and execution
  sequences for each market category. Designed to bootstrap @trader:axiom with exchange-
  specific opportunity pipelines. Load alongside exploits.md.
type: reference
version: 5.1.0
---

# STRATEGIES — Polymarket Trading Playbooks

Each strategy is a self-contained pipeline: Discovery → Edge Verification → Gate Check → Execute.
These feed into the @trader cycle structure. Run the applicable playbooks during Step 2 (DISCOVER).

---

## Strategy 1: Daily BTC Strike Sniping

**Category:** Crypto / Oracle arbitrage  
**Edge source:** Chainlink oracle vs. strike price  
**Confidence:** Highest available. Verifiable in <30 seconds.  
**Best time:** Final 90 minutes before 4 PM UTC; first 30 minutes of day (fresh strikes)

### Discovery
```python
# 1. Get current oracle price (the settlement source)
btc_price = axiom__chainlink_btc_price()

# 2. Get all active BTC strikes, soonest expiry first
markets = web_fetch(
    "https://gamma-api.polymarket.com/events"
    "?closed=false&active=true&title=Bitcoin+above"
    "&order=endDate&ascending=true&limit=15"
)
```

### Edge Verification
```python
for market in markets:
    prices = json.loads(market["outcomePrices"])
    yes_price = float(prices[0])
    
    # Parse strike from title: "Bitcoin above $95,000 on April 18?"
    strike = parse_strike(market["title"])
    
    distance = btc_price - strike   # positive = BTC above strike
    
    # Edge matrix:
    if distance > 5000 and yes_price < 0.95:
        edge = "STRONG — oracle firmly above, YES underpriced"
    elif distance > 2000 and yes_price < 0.88:
        edge = "MODERATE — meaningful distance, check expiry time"
    elif distance < -5000 and (1 - yes_price) < 0.95:  # NO side
        edge = "STRONG NO — oracle firmly below"
    else:
        continue  # skip
```

### Execution
```python
token_ids = json.loads(market["clobTokenIds"])
yes_token = token_ids[0]

book = axiom__market_book(yes_token)
best_ask = float(book["asks"][0][0])

# Snipe at best ask (FAK for immediate fill)
size = calculate_kelly_size(p_true=0.97, entry=best_ask, balance=available)
axiom__axiom_buy(yes_token, best_ask, size)
axiom__axiom_stop_loss(yes_token, best_ask * 0.5, shares)
```

### Timing Notes
- Strikes expire at **4:00 PM UTC** (noon EDT, 9 AM PDT)
- In final 30 minutes: YES on firmly in-the-money strikes should approach $0.97+
- If YES < $0.93 with <30 min to expiry and BTC $3000+ above strike → strong snipe
- Check Chainlink price, not Coinbase — they differ by up to 1-2 minutes during fast moves

---

## Strategy 2: Pre-Game Sports

**Category:** Sports  
**Edge source:** CEX/sportsbook spread → implied probability gap vs. PM price  
**Confidence:** Medium. Requires spread-to-probability conversion.  
**Best time:** 30 minutes to 2 hours before game start (before auto-cancel)

### Discovery
```python
from datetime import date
today = date.today().strftime("%Y%m%d")

# Get live scoreboards (games not yet started)
nba = web_fetch(f"https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard?dates={today}")
mlb = web_fetch(f"https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard?dates={today}")
nhl = web_fetch(f"https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard?dates={today}")

# Filter: only games not yet started (status.type.state == "pre")
upcoming = [g for g in all_games if g["status"]["type"]["state"] == "pre"]
```

### Edge Verification
```python
for game in upcoming:
    home = game["competitions"][0]["competitors"][0]
    away = game["competitions"][0]["competitors"][1]
    
    # Get moneyline odds
    home_ml = home.get("odds", {}).get("moneyline")
    
    # Convert moneyline to implied probability
    if home_ml < 0:
        p_home = abs(home_ml) / (abs(home_ml) + 100)
    else:
        p_home = 100 / (home_ml + 100)
    
    # Search Polymarket for this game
    query = f"{home['team']['displayName']} {away['team']['displayName']}"
    pm_market = axiom__market_search(query)
    
    if not pm_market:
        continue
    
    pm_yes_price = get_yes_price(pm_market)  # PM implied prob for home win
    
    edge = p_home - pm_yes_price  # positive = home underpriced on PM
    if abs(edge) > 0.05:          # 5% minimum edge threshold
        candidates.append({market: pm_market, edge: edge, side: "YES" if edge > 0 else "NO"})
```

### Spread → Implied Probability Quick Reference
```
Point Spread  Favorite Win%   Notes
   -1.5         54%           Near coin flip
   -3.0         60%           Home field advantage level
   -5.5         68%           Moderate favorite
   -7.0         72%           Clear favorite
   -8.5         76%
   -10.0        80%
   -12.5        84%
   -14.0        87%
   -17+         90%+          Heavy favorite
```

**Moneyline is more precise.** Use spread only when moneyline is unavailable.

### Execution Notes
- Sports markets auto-cancel at `gameStartTime` — ensure game hasn't started
- 1-second matching delay on sports markets (per Polymarket docs): FAK orders still work, just submit and wait
- Set stop-loss immediately: outcomes are binary, no averaging down

---

## Strategy 3: Live Score Sniping (Intermediate)

**Category:** Sports / Timing  
**Edge source:** Live score update → PM price lag (minutes)  
**Confidence:** High when score is decisive  
**Best time:** Major scoring events in 4th quarter / final period

### Mechanism
When a heavy favorite goes up by 3 touchdowns in Q3, PM markets often still
show 25% win probability for the underdog. ESPN updates in 3-5 seconds.
PM takes 30-90 seconds to reprice.

### Discovery
```python
# Poll ESPN every 30 seconds for score updates
game = web_fetch(f"https://site.api.espn.com/apis/site/v2/sports/football/nfl/summary?event={game_id}")
score_diff = home_score - away_score
time_remaining = game["status"]["displayClock"]

# Calculate implied win probability from score/time
# (use a scoring model or lookup table)
p_win_given_score = win_probability_model(score_diff, time_remaining, sport)

# Compare to PM price
pm_market = axiom__market_search(f"{home_team} moneyline")
pm_price = get_yes_price(pm_market)

if p_win_given_score - pm_price > 0.08:  # 8% edge (higher bar for live)
    # Execute
```

### Caveats
- Only valid when sport + score + time clearly predicts outcome
- Don't trade on "momentum" — only on score-based probability
- High variance: a single play can reverse the edge

---

## Strategy 4: Information Asymmetry (News/Events)

**Category:** Politics / Economics / Social  
**Edge source:** Official data/announcement vs. PM market lag  
**Confidence:** High for verifiable facts, low for interpretation  

### Playbook
```
1. Identify: What event does this market resolve on? (read resolution criteria)
2. Verify: Does an authoritative source already have the answer?
3. Gap: Is PM still pricing uncertainty when the answer is known?
4. Execute: Buy the correct side
```

### Common Information Sources
| Category | Source | Update Frequency |
|----------|--------|-----------------|
| Employment/CPI | BLS (bls.gov) | Monthly, scheduled |
| Fed decisions | federalreserve.gov | 8x per year |
| Earnings | SEC EDGAR, company IR | Quarterly |
| Weather | api.weather.gov (NOAA) | 6-hourly |
| Elon tweets | Twitter/X search | Real-time |
| Sports scores | ESPN API | Real-time (3-5s) |
| Political | AP, Reuters | Breaking |

### Tweet Count Markets
Polymarket runs "Will Elon Musk tweet X times this week?" markets.
```python
# Search Twitter/X for recent Elon tweets
results = web_search("elon musk tweets today site:twitter.com OR site:x.com")
# Count verified tweets for the period
# Compare to PM implied probability
```

---

## Strategy 5: Resolution Sniping

**Category:** Arb / Near-risk-free  
**Edge source:** Known outcome + residual UMA window  
**Confidence:** Very high when outcome is verifiable  

### Trigger Conditions
```
Market endDate has passed AND
Outcome is known AND verifiable AND
Market is still tradeable AND
YES price < $0.96 (leaving ≥ 2% return after fees)
```

### Discovery
```python
# Search for recently expired markets with outcome known
markets = web_fetch(
    "https://gamma-api.polymarket.com/events"
    "?closed=false&active=false&resolved=false"
    "&order=endDate&ascending=false&limit=50"
)
# "active=false" but "resolved=false" → expired but not yet settled

for market in markets:
    end_date = parse(market["endDate"])
    if end_date > now - timedelta(hours=2):  # Within UMA window
        # Verify outcome externally
        verify_outcome(market["title"])
```

### Sizing
Resolution sniping is near-risk-free. Size more aggressively:
```python
# Still use Kelly, but p_true = 0.995 (essentially certain)
# With $3.50 cap, try to use full available budget up to cap
size = min(available_capital, 3.50)
# Buy YES at best ask (should be $0.92-$0.98)
```

---

## Strategy 6: Multi-Outcome Negative Risk Scan

**Category:** Structural arb  
**Edge source:** Sum of YES prices < $1.00  
**Confidence:** 100% mathematical when condition holds  

### Scan
```python
# Multi-outcome events have many markets under one event
events = web_fetch(
    "https://gamma-api.polymarket.com/events"
    "?closed=false&active=true&limit=100"
)

for event in events:
    if len(event["markets"]) < 3:
        continue  # Not multi-outcome enough
    
    prices = [float(p) for m in event["markets"] 
              for p in json.loads(m["outcomePrices"])[:1]]  # YES price each
    total = sum(prices)
    
    if total < 0.97:
        gross_arb = 1.00 / total - 1.00
        # Query live taker fee per leg via CLOB /fee-rate/{token_id}
        # (returns basis points; typical 10–30 bps, NOT 2%)
        net_arb = gross_arb - (taker_fee_rate * len(prices))
        if net_arb > 0.03:
            print(f"ARBNEG: {event['title']} — {net_arb:.1%} net arb")
```

---

## Candidate Ranking Formula

All discovered candidates are ranked by:
```python
score = ev * liquidity_factor * confidence_factor * time_factor

where:
  ev               = p_true - entry_price  (primary driver)
  liquidity_factor = min(1.0, book_depth_at_price / 10.0)  # penalize thin books
  confidence_factor = 1.0 (oracle/verifiable) | 0.7 (model-based) | 0.4 (opinion)
  time_factor      = 1.0 (>2h to expiry) | 1.2 (final 2h, outcome clear) | 0.5 (<10min)

Top candidate by score → run 9-gate contract → execute or next candidate
```
