---
description: Demo - four parallel coders build the same service in Go, Rust, TypeScript and Python, then race them.
agent: lead
---
Run a polyglot race in ~/demo/polyglot (create it, git init).

Spec, identical for all four: an HTTP service on its own port (Go 8201, Rust 8202, TypeScript 8203,
Python 8204) with `GET /health` and `POST /stats` that takes a JSON array of numbers and returns
count, mean, median, p95, min, max and standard deviation. Validate input: a non-array or a
non-number gives HTTP 400 with a JSON error. Include unit tests and a README per language.
Extra requirements (may be empty): $ARGUMENTS

Dispatch four `coder` subagents in ONE message, one per language, each owning its own
subdirectory (go/, rust/, ts/, python/). Use only the standard library plus at most one
well-known HTTP framework per language. Each coder must leave zero language-server
diagnostics and green tests.

Then: start all four, check that they give identical answers for the same 5 inputs (including
the error cases), and benchmark each with 2000 requests at 16 concurrent clients (write a small
load generator in Go). Stop the services. Report a table: language, lines of code, test count,
p50 and p99 latency, requests per second, and one sentence per language on what was hard.

Scope: one build wave and at most one `reviewer` pass. Put the reviewer's findings in the
report as a "known gaps" list; do not start a second wave of coders to fix them. Commit once
the table is written, then stop.
