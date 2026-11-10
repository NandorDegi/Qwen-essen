---
description: Build a feature end to end with the team - plan, parallel coders, tests, review, browser check.
agent: lead
---
Build this with the team: $ARGUMENTS

Work in a new git repository under ~/demo/ unless I name another directory.
Plan, then run the independent parts in parallel through `coder` subagents, have `tester` cover
them, integrate and run everything, send the diff to `reviewer`, and if there is a UI let
`browser-qa` click through it. Fix what they find. Finish with a short report and the evidence.
