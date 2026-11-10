---
title: "<Service or system name>"
tags: [service, <domain-tag>, layer/architecture, topic/<topic>]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: <live | planned | retired>
---

# <Service or system name>

> <One paragraph: what it is, what it does for the environment, and where it runs.>

## Role

<What problem it solves. Which systems depend on it, and which systems it depends on.>

## Where it runs

| Item | Value |
|---|---|
| Host | <host name> (verified YYYY-MM-DD) |
| Version | <version> (verified YYYY-MM-DD) |
| Ports | <port and protocol> |
| Owner | <team or role> |

## How it connects

```
<source> → <this service> → <consumer>
```

<One paragraph for each connection: protocol, direction, authentication. Write the location of each credential. Never write its value.>

## Known limits

- <A limit, with the date and the source of the observation.>

## Decisions

- [[D-NNN-<slug>|D-NNN]] — <the decision that shaped this service>

## Parts

- [[<runbook>]] — <the procedures for this service>

## Related

[[<parent overview>]]
