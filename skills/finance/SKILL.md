---
name: finance
description: |
  Research-grade quantitative finance. Loads QUANT.md (mathematical toolkit: stochastic
  calculus, derivative pricing, risk metrics, portfolio theory, numerical methods) and
  MODELS.md (applied model library: Black-Scholes, Heston, factor models, Monte Carlo).
  Imbues any agent with the working knowledge of a PhD-level financial engineer.
user-invocable: true
metadata:
  openclaw:
    emoji: "📐"
---

# FINANCE — Quantitative Finance Skill

This skill loads two dense reference modules. Both should be read into context for full capability.

| Module | Content |
|--------|---------|
| `QUANT.md` | Core mathematical toolkit — stochastic calculus, probability, linear algebra, optimization, risk theory |
| `MODELS.md` | Applied model library — Black-Scholes, Greeks, Heston, factor models, Monte Carlo, backtesting |

## Activation

```
Read QUANT.md   → mathematical foundations + quantitative reasoning process
Read MODELS.md  → specific models, formulas, implementation patterns
```

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
