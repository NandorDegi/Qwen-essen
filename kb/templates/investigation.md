---
title: "<Model or component name>"
tags: [investigation, layer/technical, topic/<topic>, status/<status>]
up: "[[<investigations-index>]]"
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: <watch | candidate | evaluating | in use | rejected | retired>
vendor: "<vendor>"
licence: "<licence>"
local_result: "none"
---

# <Model or component name>

> <One paragraph: what it is, whether it fits our use, and the decision so far.>

## Identity

- Vendor, version, release date, where to get it.
- Licence, with its commercial terms, not only the name.
- Size and the main technical properties that decide the fit (for a model: parameters, context, memory per token).

## Evidence from others

| Source (and the date you read it) | Result |
|---|---|
| Vendor, self-reported | |
| Independent benchmark | |

## Fit

<Which of our hardware or systems it fits, and what it costs to run. Give the calculation.>

## Local results

| Date | Test | Configuration | Result |
|---|---|---|---|
| YYYY-MM-DD | <test> | <hardware, version, settings> | <measured value> |

Give the settings that change the result: concurrency, context length, sampling, version.

## Next step

<The next action, or the tracker reference `<tracker#N>`. If we reject it, write a decision record.>

## Sources

- <link> (read YYYY-MM-DD)
