---
name: finance:models
description: |
  Applied quantitative model library. Black-Scholes derivation and Greeks, Heston stochastic
  volatility, jump-diffusion, term structure models, factor models, and backtesting framework.
  Companion to QUANT.md — use together for full financial engineering capability.
type: reference
---

# MODELS — Applied Quantitative Model Library

Reference implementations and intuitions for the models most used in quantitative finance.
State assumptions before applying any model. Never use a formula you cannot derive.

---

## I. Black-Scholes Model

### Assumptions
1. Underlying follows GBM: dS = μS dt + σS dW
2. Constant volatility σ (biggest weakness)
3. Continuous trading, no transaction costs
4. No dividends (base case)
5. Risk-free rate r is constant

### The PDE (from Itô + no-arbitrage)
```
∂V/∂t + ½σ²S²·∂²V/∂S² + rS·∂V/∂S − rV = 0

Boundary conditions determine the derivative:
  European call: V(S,T) = max(S−K, 0)
  European put:  V(S,T) = max(K−S, 0)
```

### Closed-Form Solution
```
Call:  C = S·N(d₁) − K·e^(−rT)·N(d₂)
Put:   P = K·e^(−rT)·N(−d₂) − S·N(−d₁)

d₁ = [ln(S/K) + (r + σ²/2)T] / (σ√T)
d₂ = d₁ − σ√T

N(·) = standard normal CDF

Put-Call Parity (model-free):  C − P = S − K·e^(−rT)
```

### The Greeks
```
Delta  Δ = ∂V/∂S       Call: N(d₁)        Put: N(d₁)−1
           Hedge ratio — how many shares to hold per option to be market-neutral.

Gamma  Γ = ∂²V/∂S²     = N'(d₁)/(Sσ√T)
           Rate of change of delta. High gamma = delta changes fast near expiry.
           Long gamma = profits from large moves (long options).

Theta  Θ = ∂V/∂t       (negative for long options — time decay)
           Call: −(Sσ·N'(d₁))/(2√T) − rK·e^(−rT)·N(d₂)
           Put : −(Sσ·N'(d₁))/(2√T) + rK·e^(−rT)·N(−d₂)

Vega   ν = ∂V/∂σ       = S√T·N'(d₁)                    (call = put)
           Sensitivity to volatility. Options are long vega by default.
           1 vega unit = $ change per 1% move in σ.

Rho    ρ = ∂V/∂r       Call:  KT·e^(−rT)·N(d₂)
                       Put : −KT·e^(−rT)·N(−d₂)
           Usually smallest; matters for long-dated options.
```

Second-order Greeks worth knowing:
- **Vanna** = ∂²V/∂S∂σ — sensitivity of delta to vol (or vega to spot). Hedge of skew-trading books.
- **Volga** (vomma) = ∂²V/∂σ² — sensitivity of vega to vol. OTM-rich books are long volga.
- **Charm** = ∂²V/∂S∂t — delta decay; relevant near expiry for pin-risk management.

### Volatility Surface & Smile
Black-Scholes implies a flat vol surface. Real markets show:
- **Vol smile:** OTM puts and calls trade at higher IV than ATM (fat tails)
- **Vol skew:** puts more expensive than calls (crash risk premium)
- **Term structure:** vol varies across expiry

Implied vol is the market's BS-inverted price. It is observable. Historical vol is realized.
**Vol risk premium** = IV − HV > 0 on average (sellers of options earn a premium).

### American Options & Early Exercise
Black-Scholes prices **European** options (exercise only at T). American options allow
exercise at any t ≤ T and satisfy a **free-boundary** problem: the holder chooses τ ≤ T
to maximize E[e^(−rτ)·payoff(S_τ)].
```
V(S,t) = max( intrinsic(S),  continuation value )
       ≥ intrinsic at all (S,t)        [no early exercise gives away value]
```
Key facts:
- **American call on a non-dividend stock = European call** (never optimal to exercise early; carry the strike).
- **American put** is strictly more valuable than the European put. Early exercise is
  optimal when S falls below a critical boundary S*(t) that rises monotonically toward K
  as t → T.
- With **dividends**, early call exercise can be optimal just before the ex-dividend date.

Numerical methods:
- **Binomial tree (CRR)** — discrete-time, easy to implement, naturally handles early
  exercise via backward induction with `V = max(intrinsic, discounted continuation)`.
- **Longstaff–Schwartz (LSM)** — regression-based Monte Carlo for high-dimensional or
  path-dependent Americans; regress continuation value on basis functions (e.g.,
  Laguerre polynomials in S) at each exercise date.
- **PSOR / projected SOR on the BS PDE** — solve the linear-complementarity problem
  directly; convergent but slower than LSM in high dimensions.

---

## II. Heston Stochastic Volatility Model

### Model
```
dS = μS dt + √v · S dW₁
dv = κ(θ − v) dt + ξ√v dW₂

Where:
  v    = instantaneous variance (not vol — note the √v in dS)
  κ    = mean reversion speed of variance
  θ    = long-run mean variance
  ξ    = vol-of-vol (volatility of the variance process)
  ρ    = correlation between dW₁ and dW₂ (typically negative: −0.7 for equities)
  
Feller condition: 2κθ > ξ²  → ensures variance stays positive
```

### Why Use Heston
- Captures vol smile/skew without fitting a different σ per strike
- Variance is mean-reverting (consistent with empirical observation)
- Has semi-closed-form solution via characteristic function + Fourier inversion
- ρ < 0 → stocks fall when vol rises → realistic

### Pricing
No simple closed form. Use the characteristic function of log-S under the two probability
measures (delta-measure for P₁, risk-neutral measure for P₂):
```
C = S·P₁ − K·e^(−rT)·P₂                          (Heston 1993)

P_j = ½ + (1/π) ∫₀^∞ Re[ e^(−iu·ln(K)) · φ_j(u; x, v, T) / (iu) ] du,   j = 1,2

φ_j(u; x, v, T) = exp( C_j(u,T) + D_j(u,T)·v + iu·x ),   x = ln(S_t)

D_j(u,T) = ((b_j − ρξui + d_j) / ξ²) · (1 − e^(d_j·T)) / (1 − g_j·e^(d_j·T))
C_j(u,T) = r u i T + (κθ/ξ²) · [ (b_j − ρξui + d_j)T − 2 ln((1 − g_j·e^(d_j·T))/(1 − g_j)) ]

d_j = √( (ρξui − b_j)² − ξ²(2 u_j ui − u²) )
g_j = (b_j − ρξui + d_j) / (b_j − ρξui − d_j)

with  (u₁, b₁) = (½, κ − ρξ),  (u₂, b₂) = (−½, κ).
```

P₁ is the delta of the call (= probability the option is ITM under the stock-numéraire
measure); P₂ is the risk-neutral probability of expiring ITM. The integral is computed
numerically — Carr–Madan FFT is the standard fast path; `scipy.integrate.quad` is fine for
single-strike pricing. Watch the branch cut of the complex logarithm: use the
**Albrecher / "Little Heston Trap"** formulation (swap signs in d_j and g_j) for stable
long-maturity pricing.

Calibration: fit (κ, θ, ξ, ρ, v₀) to a strip of market IVs by minimizing weighted squared
errors. The objective is non-convex — seed from sensible defaults (e.g., θ ≈ ATM IV²,
v₀ ≈ θ, κ ∈ [1,5], ρ ∈ [−0.8, −0.3], ξ ∈ [0.2, 0.6] for equity indices).

---

## III. Jump-Diffusion (Merton Model)

### Model
```
dS/S = (μ − λk̄) dt + σ dW + (J−1) dN

Where:
  N = Poisson process with intensity λ (jumps per year)
  J = jump size, log-normal: ln(J) ~ N(μ_J, σ_J²)
  k̄ = E[J−1] = e^(μ_J + σ_J²/2) − 1
```

### Pricing (Merton)
```
C_Merton = Σ_{n=0}^∞ [e^(−λ'T)(λ'T)^n / n!] · BS(S, K, r_n, σ_n, T)

λ' = λ(1 + k̄)
r_n = r − λk̄ + n·μ_J/T
σ_n² = σ² + n·σ_J²/T
```

Captures crash risk better than BS. Used when you expect discrete large moves (earnings, FOMC, events).

---

## IV. Term Structure Models (Interest Rates)

### Vasicek (1977)
```
dr = κ(θ − r) dt + σ dW

Mean-reverting rate. Can go negative (weakness).
Bond price: P(t,T) = A(t,T)·e^(−B(t,T)·r)  [closed form]
```

### Cox-Ingersoll-Ross (CIR)
```
dr = κ(θ − r) dt + σ√r dW

Cannot go negative (if 2κθ > σ²). More realistic.
Bond price: closed form via A, B functions.
```

### Nelson-Siegel (Yield Curve Fitting)
```
y(τ) = β₀ + β₁·(1−e^(−λτ))/(λτ) + β₂·[(1−e^(−λτ))/(λτ) − e^(−λτ)]

β₀ = long-run level
β₁ = slope (short minus long)
β₂ = curvature (hump)
λ  = decay parameter

Fit to observed yields via OLS. Used by central banks and fixed income desks.
```

---

## V. Factor Models

### Single-Factor (CAPM)
```
E[R_i] = R_f + β_i · (E[R_m] − R_f)

β_i = Cov(R_i, R_m) / Var(R_m)   [systematic risk]

Alpha (α): actual return minus CAPM prediction. Positive alpha = outperformance.
```

### Fama-French Three-Factor
```
R_i − R_f = α + β_MKT·(R_m−R_f) + β_SMB·SMB + β_HML·HML + ε

SMB = Small Minus Big (size premium)
HML = High Minus Low book-to-market (value premium)

Five-Factor adds: RMW (profitability), CMA (investment)
```

### Arbitrage Pricing Theory (APT)
```
R_i = α_i + Σ_k β_{ik}·F_k + ε_i

F_k = factors (macro: GDP, inflation, credit spread, etc.)
β_{ik} = factor loadings
ε_i = idiosyncratic (diversifiable) risk

No-arb implies: E[R_i] = R_f + Σ_k β_{ik}·λ_k
Where λ_k = factor risk premium.
```

### PCA Factor Extraction
```python
from sklearn.decomposition import PCA
import numpy as np

# returns: (T x N) matrix of asset returns
pca = PCA(n_components=k)
factors = pca.fit_transform(returns)         # (T x k) factor realizations
loadings = pca.components_                   # (k x N) factor loadings
explained = pca.explained_variance_ratio_   # variance explained per factor

# Residuals = idiosyncratic returns
residuals = returns - factors @ loadings
```

---

## VI. Monte Carlo: Advanced Patterns

### Variance Reduction
```python
# Antithetic variates
Z = np.random.standard_normal(n//2)
Z_anti = np.concatenate([Z, -Z])  # E[Z] = 0, variance halved

# Control variates
# Corrrelate payoff with a known-EV variable (e.g., the underlying)
S_T_sim = S0 * np.exp((r - 0.5*sigma**2)*T + sigma*np.sqrt(T)*Z)
payoff = np.maximum(S_T_sim - K, 0)
E_S_T = S0 * np.exp(r*T)  # known
c = -np.cov(payoff, S_T_sim)[0,1] / np.var(S_T_sim)
payoff_cv = payoff + c * (S_T_sim - E_S_T)
price = np.exp(-r*T) * np.mean(payoff_cv)
```

### Path-Dependent Options
```python
# Asian option (average price)
paths = simulate_gbm(S0, r, sigma, T, dt=1/252, n_paths=50_000)
avg_price = paths.mean(axis=1)
payoff = np.maximum(avg_price - K, 0)

# Barrier option (knock-out)
max_price = paths.max(axis=1)
payoff = np.maximum(paths[:,-1] - K, 0) * (max_price < barrier)
```

---

## VII. Backtesting Framework

### Core Principles
1. **No look-ahead bias:** signals use only data available at decision time
2. **Realistic costs:** include bid-ask spread, slippage, commissions
3. **Out-of-sample test:** in-sample fit means nothing; OOS performance is signal
4. **Walk-forward:** roll the training window forward; don't train on the whole dataset

### Performance Metrics
```python
def backtest_metrics(returns, rf=0.0, periods_per_year=252):
    excess = returns - rf/periods_per_year
    sharpe = excess.mean() / returns.std() * np.sqrt(periods_per_year)
    
    cum = (1 + returns).cumprod()
    running_max = cum.cummax()
    drawdown = (cum - running_max) / running_max
    mdd = drawdown.min()
    
    calmar = returns.mean() * periods_per_year / abs(mdd)
    
    return {"sharpe": sharpe, "max_drawdown": mdd, "calmar": calmar,
            "ann_return": returns.mean() * periods_per_year,
            "ann_vol": returns.std() * np.sqrt(periods_per_year)}
```

### Multiple Testing Problem
Running 100 strategy variations and picking the best one inflates Sharpe by:
```
E[max Sharpe from N trials] ≈ √(2 ln N)  (for standard normal)

Correction: use Bonferroni (α/N) or Benjamini-Hochberg for p-value adjustment.
Report: number of strategies tried, selection method, OOS Sharpe.
```

### Walk-Forward Example
```python
def walk_forward(data, train_window, test_window, strategy_fn):
    results = []
    for start in range(0, len(data)-train_window-test_window, test_window):
        train = data[start : start+train_window]
        test  = data[start+train_window : start+train_window+test_window]
        params = strategy_fn.fit(train)
        oos_returns = strategy_fn.predict(test, params)
        results.append(oos_returns)
    return pd.concat(results)
```

---

## VIII. Implementation Notes

### Python Stack
```
numpy / scipy     → linear algebra, stats, optimization
pandas            → time series, data manipulation
statsmodels       → regression, ARIMA, cointegration tests
scikit-learn      → PCA, factor models, ML signals
py_vollib         → Black-Scholes, Greeks (fast C backend)
yfinance / quandl → market data
matplotlib / seaborn → visualization
```

### Rust for Performance-Critical Paths
```rust
// Monte Carlo is embarrassingly parallel — ideal for Rust + rayon
use rayon::prelude::*;

fn simulate_paths(s0: f64, mu: f64, sigma: f64, n_paths: usize) -> Vec<f64> {
    (0..n_paths).into_par_iter().map(|_| {
        // per-path simulation using rand_distr
        let z: f64 = Normal::new(0.0, 1.0).unwrap().sample(&mut rand::thread_rng());
        s0 * ((mu - 0.5 * sigma * sigma) + sigma * z).exp()
    }).collect()
}
// 10-100x faster than Python for large n_paths
```

### Numerical Precision
- Use `float64` (not `float32`) for pricing — 1bp errors compound
- Log-space arithmetic for products of many small probabilities (avoid underflow)
- Cache characteristic function evaluations in Fourier pricing
