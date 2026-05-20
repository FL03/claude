---
name: finance:quant
description: |
  Research-grade quantitative analyst module. Stochastic calculus, probability theory,
  linear algebra, optimization, risk theory, and market microstructure. Dense mathematical
  reference for PhD-level financial engineering work.
type: reference
---

# QUANT — Mathematical Toolkit for Financial Engineering

You reason from first principles. Every claim is supported by a formula, every formula by an assumption, every assumption stated explicitly.

---

## I. Quantitative Mindset

**Distributions, not points.** Asset returns are random variables. Report E[X] ± σ, not "X will be Y."

**All models are wrong. Some are useful.** State model assumptions before applying. Black-Scholes assumes constant vol — say so, then use it, then check the Greeks for where it breaks.

**Edge = P(true) − P(implied).** You have edge when your probability estimate diverges from the market's by enough to overcome transaction costs. Quantify both numbers. If you cannot, you have no edge.

**Expected Value is the foundation:**
```
EV = Σ p_i × x_i

Binary (pays $1 or $0):
  EV = p_true − entry_price
  If EV ≤ 0 → no edge. Walk away.
```

---

## II. Stochastic Calculus

### Brownian Motion (Wiener Process)
Standard Brownian motion W_t satisfies:
- W_0 = 0
- Increments are independent: W_t − W_s ⊥ W_s for t > s
- W_t − W_s ~ N(0, t−s)
- Paths are continuous but nowhere differentiable

### Geometric Brownian Motion (GBM)
The canonical model for asset prices S_t:
```
dS = μS dt + σS dW_t

Solution:  S_t = S_0 · exp((μ − σ²/2)t + σW_t)

Where:
  μ = drift (expected return)
  σ = volatility (annualized)
  dW_t = Brownian increment ~ N(0, dt)
```

### Itô's Lemma
For f(S, t) where S follows a diffusion:
```
df = (∂f/∂t + μS·∂f/∂S + ½σ²S²·∂²f/∂S²) dt + σS·∂f/∂S dW_t

Key: the ½σ²S²·∂²f/∂S² term (Itô correction) has no classical analogue.
It arises because Brownian paths have non-zero quadratic variation: (dW)² = dt.
```

### Ornstein-Uhlenbeck (Mean Reversion)
```
dX = θ(μ − X) dt + σ dW_t

Where:
  θ = mean reversion speed (half-life = ln(2)/θ)
  μ = long-run mean
  σ = volatility

Used for: interest rates, spreads, volatility, pairs trading signals.
```

---

## III. Probability & Statistics

### Key Distributions in Finance
| Distribution | Use Case | Parameters |
|---|---|---|
| Normal N(μ,σ²) | Returns (approx), log-returns | mean, variance |
| Log-Normal | Asset prices (GBM solution) | μ, σ of log |
| Student-t | Fat-tailed returns | ν degrees of freedom |
| Poisson | Jump arrivals | λ rate |
| Exponential | Time between events | λ |

### Moments That Matter
```
E[X]        = mean (first moment)
Var[X]      = E[(X−μ)²] (second central moment)
Skewness    = E[(X−μ)³] / σ³   (positive = right tail)
Kurtosis    = E[(X−μ)⁴] / σ⁴  (Normal=3; "excess" = Kurt−3)

Heavy tails: kurtosis >> 3. Financial returns almost always have excess kurtosis.
```

### Bayesian Updating
```
P(H|E) = P(E|H) · P(H) / P(E)

Workflow:
  Prior    → market-implied probability (crowd estimate)
  Evidence → authoritative real-time source (oracle, API, official data)
  Posterior → updated estimate, weighted by evidence reliability

Confidence tiers:
  HIGH   → authoritative + real-time + verifiable → trust your estimate
  MEDIUM → authoritative but lagging → shade toward market price
  LOW    → unverifiable or opinion → DO NOT act
```

### Law of Large Numbers / CLT
- Individual trades: high variance
- Over N independent trades: portfolio return → N·E[EV], σ_portfolio → σ·√N
- **Implication:** Consistent edge compounds. Variance is the enemy of compounding, not loss.

---

## IV. Linear Algebra & Portfolio Theory

### Markowitz Mean-Variance Optimization
```
Given N assets with expected returns μ (Nx1) and covariance matrix Σ (NxN):

Minimize portfolio variance:  min w'Σw
Subject to:                   w'μ = μ_target
                              w'1 = 1  (fully invested)

Solution via Lagrangian gives the efficient frontier.
Optimal weights: w* = Σ⁻¹μ / (1'Σ⁻¹μ)  [max Sharpe, unconstrained]
```

### Covariance Matrix
```
Σ_ij = ρ_ij · σ_i · σ_j

Diagonal: Σ_ii = σ_i²  (variance of asset i)
Off-diagonal: Σ_ij = covariance between i and j

In practice: estimate from historical returns, then apply shrinkage
(Ledoit-Wolf) to reduce estimation error in high dimensions.
```

### Principal Component Analysis (PCA) for Factor Models
```
Σ = V·Λ·V'  (eigendecomposition)

First eigenvector = market factor (explains most variance)
Subsequent eigenvectors = style factors (value, momentum, size...)

Use: reduce 500-stock covariance matrix to k<<500 factors.
Fama-French 3-factor: market, HML (value), SMB (size)
```

### Correlation vs. Causation in Finance
Correlation kills in concentrated books. Two positions with ρ=0.8 are effectively one big position with 80% of the diversification benefit gone. Effective N:
```
N_eff = (Σ σ_i)² / Σ σ_i²     [Herfindahl-based]
```

---

## V. Optimization

### Kelly Criterion (Optimal Bet Sizing)
```
Full Kelly:  f* = (b·p − q) / b

Half Kelly:  f  = f* / 2   ← ALWAYS USE THIS

Where:
  b = net odds paid (profit per unit risked)
  p = your estimated probability of winning
  q = 1 − p

For binary prediction markets (pays $1.00 or $0.00):
  b = (1 − entry_price) / entry_price
  f* = p − entry_price  (if entry_price < p, else negative → wrong side)

Bet = f × bankroll
If f < 0 → you're on the wrong side
If half-Kelly < min trade size → edge too thin, pass
```

**Why half-Kelly:** Full Kelly maximizes long-run log-wealth growth but has brutal drawdowns.
Half-Kelly gives ~75% of the growth rate with ~50% the drawdown.

### Utility Maximization
```
Maximize E[U(W)] where U is a utility function.

Common choices:
  Log utility:        U(W) = ln(W)   → leads to Kelly
  CARA (exponential): U(W) = −e^(−αW) → constant absolute risk aversion
  CRRA (power):       U(W) = W^(1−γ)/(1−γ) → constant relative risk aversion

Implication: rational agents don't maximize E[W], they maximize E[U(W)].
A 50% chance of doubling vs 50% chance of ruin is EV-positive but CRRA-negative for γ>0.
```

### Lagrangian Optimization (Constrained)
```
min f(x) subject to g(x) = 0, h(x) ≤ 0

L(x,λ,μ) = f(x) + λ'g(x) + μ'h(x)

KKT conditions: ∇L = 0, μ_i ≥ 0, μ_i·h_i(x) = 0

Used for: portfolio optimization, option replication, constrained sizing.
```

---

## VI. Risk Metrics

### Value at Risk (VaR)
```
VaR_α = −F⁻¹(1−α) · W  [at confidence level α]

VaR_95%: 95% of days, loss will not exceed this value
VaR_99%: 99% confidence

Parametric (normal returns): VaR = μ − z_α · σ
  z_95% = 1.645, z_99% = 2.326

Weakness: VaR ignores what happens in the tail (the 1% or 5%).
```

### Conditional VaR (CVaR / Expected Shortfall)
```
CVaR_α = E[loss | loss > VaR_α]

This is the average loss in the worst (1−α)% of scenarios.
CVaR is coherent (subadditive); VaR is not.
Always report both.
```

### Sharpe Ratio
```
Sharpe = (E[R] − R_f) / σ(R)

Where R_f = risk-free rate, σ(R) = standard deviation of returns.
Annualized: multiply numerator by T, denominator by √T.

Sortino ratio: replace σ(R) with σ_downside (semi-deviation below target).
Better for asymmetric return distributions.
```

### Maximum Drawdown (MDD)
```
MDD = max over all periods of (Peak − Trough) / Peak

Calmar ratio = Annualized Return / MDD   [higher is better]

Drawdown rules (applied to trading accounts):
  After 1 loss:               reduce size 25%
  After 2 consecutive losses: skip next cycle
  After 3 consecutive losses: stop 2+ hours, reassess
```

---

## VII. Numerical Methods

### Monte Carlo Simulation
```python
# GBM path simulation
import numpy as np

def simulate_gbm(S0, mu, sigma, T, dt, n_paths):
    n_steps = int(T / dt)
    Z = np.random.standard_normal((n_paths, n_steps))
    increments = (mu - 0.5*sigma**2)*dt + sigma*np.sqrt(dt)*Z
    log_returns = np.cumsum(increments, axis=1)
    paths = S0 * np.exp(log_returns)
    return paths  # shape: (n_paths, n_steps)

# Option pricing via MC
def price_european_call(S0, K, r, sigma, T, n_paths=100_000):
    Z = np.random.standard_normal(n_paths)
    S_T = S0 * np.exp((r - 0.5*sigma**2)*T + sigma*np.sqrt(T)*Z)
    payoff = np.maximum(S_T - K, 0)
    return np.exp(-r*T) * np.mean(payoff)
```

**Variance reduction techniques:**
- Antithetic variates: use Z and −Z pairs → cuts variance ~50%
- Control variates: use a correlated known-EV variable to reduce noise
- Importance sampling: oversample the tail you care about

### Finite Difference Methods (PDE Solving)
For PDEs like Black-Scholes: ∂V/∂t + ½σ²S²∂²V/∂S² + rS∂V/∂S − rV = 0
```
Discretize: S grid (j) × time grid (i)
Explicit scheme: V_j^i = f(V_{j-1}^{i+1}, V_j^{i+1}, V_{j+1}^{i+1})
  → simple but unstable for large dt
Implicit (Crank-Nicolson): solve tridiagonal system per time step
  → unconditionally stable, second-order accurate
```

---

## VIII. Market Microstructure

### Price Formation
- **Efficient markets:** prices reflect all available information. Weak (past prices), semi-strong (public info), strong (all info).
- **In practice:** markets are *nearly* efficient. Anomalies exist at edges: information asymmetry, illiquidity, microstructure noise.

### Bid-Ask Spread Components
```
Spread = Inventory cost + Adverse selection cost + Order processing cost

Inventory: market maker compensation for holding unhedged risk
Adverse selection: loss to informed traders (someone knows more than you)
Processing: operational costs

Implication: wide spreads on thinly traded markets signal illiquidity AND potential adverse selection.
```

### Price Impact
```
Temporary impact: α · (order_size / ADV)^0.5   [Almgren-Chriss]
Permanent impact: β · order_size / ADV

ADV = average daily volume

Execution cost grows nonlinearly with size. Large orders move the market against you.
Always consider impact before sizing into illiquid markets.
```

### Information Asymmetry & Edge
Edge = having information the market hasn't priced yet:
- **Oracle lag:** real-time data vs. market update frequency
- **Data freshness:** your source updates faster than market makers
- **Structural:** market mechanics create predictable mispricings
- **Temporal:** time-of-day, calendar effects

**Test for information advantage:** Can you state the edge as a falsifiable claim?
"BTC price is $X per Chainlink oracle; PM prices the $X-5000 strike at $0.85 (should be $0.97)" → verifiable.
"I think the market is too low" → not an edge.
