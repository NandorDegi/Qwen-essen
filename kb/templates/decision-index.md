---
title: Decision records
tags: [decision, index, layer/executive, topic/<topic>]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# Decision records

One short record for each decision: context, decision, consequences, date, and a link to the
detail note. The detail note holds the evidence. The record holds the reason, in a form that a
lead can read in one minute. A decision that is only in a journal or a service note cannot be
found. Give it a record here and link the two notes both ways.

**Numbering:** use the next free `D-NNN`. Never use a number again.
**Superseding:** write a new record. Set `status: superseded by D-NNN` in the old record. Do not delete the old record.

```dataview
TABLE WITHOUT ID link(file.link, id) AS "ID", title AS "Decision", decided AS "Decided", status AS "Status"
FROM "1-Executive/decisions"
WHERE id
SORT id ASC
```

## Static list (for readers without Dataview)

- [[D-001-<slug>|D-001]] — <one-line summary> (YYYY-MM-DD)
