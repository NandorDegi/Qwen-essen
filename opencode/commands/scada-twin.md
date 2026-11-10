---
description: Demo - a simulated plant, a live dashboard and anomaly detection, built by the team and checked in a browser.
agent: lead
---
Build a small industrial demo in ~/demo/plant (git init):

1. A Python simulator of a tank farm: 4 tanks with level, temperature, inflow and outflow, a pump
   per tank, sampled every second, with realistic noise and two injected faults (a stuck sensor
   and a slow leak) at random times. It writes to SQLite and publishes over a WebSocket.
2. A Go service that reads the stream, runs rolling z-score and rate-of-change detectors per
   signal, and raises alarms with a reason.
3. A TypeScript (Vite) dashboard: live trends per tank, an alarm list with acknowledge, and a
   plant overview with colour-coded state.
4. Tests for the detectors that prove both faults are caught and normal noise is not.

Use parallel `coder` subagents for the three parts against an interface you define first.
Run everything, then have `browser-qa` watch the dashboard until both faults raise alarms, with
screenshots. $ARGUMENTS
