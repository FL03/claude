---
name: finance
version: 5.1.0
description: |
  Research-grade quantitative finance. Loads QUANT.md (mathematical toolkit: stochastic
  calculus, derivative pricing, risk metrics, portfolio theory, numerical methods) and
  MODELS.md (applied model library: Black-Scholes, Heston, Merton jump-diffusion, term
  structure, factor models, Monte Carlo, backtesting). Imbues any agent with the working
  knowledge of a PhD-level financial engineer. Attach when the user asks about option
  pricing, the Greeks, implied vs realized volatility, Itô / SDEs / GBM, Value-at-Risk,
  CVaR / expected shortfall, Sharpe / Sortino / Calmar, Kelly sizing, mean-variance
  optimization, factor models (CAPM / Fama-French / APT), term-structure models (Vasicek
  / CIR / Nelson-Siegel), Monte Carlo or PDE-based pricing, or backtesting methodology.
  Analysis-only — pair with `@trader` (and an exchange skill such as `@polymarket`) for
  live execution.
user-invocable: true
metadata:
  openclaw:
    emoji: "📐"
---

# FINANCE — Quantitative Finance Skill

This skill is a primer + index. Depth lives in the two reference modules below. Read both
when the task involves any quantitative finance work — they are designed to be loaded together.

| Module | Content |
|--------|---------|
| `QUANT.md` | Core mathematical toolkit — stochastic calculus, probability, linear algebra, optimization, risk theory, market microstructure |
| `MODELS.md` | Applied model library — Black-Scholes (PDE + closed form + Greeks), Heston, Merton jump-diffusion, term structure, factor models, Monte Carlo patterns, backtesting |

## Agents

| Agent | Trigger | Job |
|-------|---------|-----|
| `analyst` | `@finance:analyze {input}` | Research-grade quantitative analysis — dispatches input through QUANT.md + MODELS.md, produces structured output (Assumptions / Methodology / Results / Caveats) |

See `finance/agents/analyst.md` for the full agent brief and dispatch template.

## Scope

This skill is **analysis-only**. It contains no trading execution logic.
For live market trading, load `@trader` and an exchange-specific skill (e.g., `@polymarket`).

## Mindset

A quant does not predict. A quant **prices risk**. Every output is a distribution with a mean,
variance, and tail. Point estimates without confidence intervals are not analysis — they are guesses.

## Canonical references

The mathematical content in `QUANT.md` and `MODELS.md` is grounded in the standard quant
finance literature. When deeper rigor is needed, cite the canonical sources rather than
re-deriving from memory:

| Topic | Canonical source |
|---|---|
| Derivatives, Greeks, Black-Scholes intuition | Hull, *Options, Futures, and Other Derivatives* |
| Stochastic calculus, martingale pricing | Bjork, *Arbitrage Theory in Continuous Time*; Shreve, *Stochastic Calculus for Finance II* |
| Practitioner-flavored pricing & vol surface | Wilmott, *Paul Wilmott on Quantitative Finance* |
| Monte Carlo methods | Glasserman, *Monte Carlo Methods in Financial Engineering* |
| Portfolio theory, factor models | Grinold & Kahn, *Active Portfolio Management*; Cochrane, *Asset Pricing* |
