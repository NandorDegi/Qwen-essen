---
title: Glossary — controlled vocabulary
tags: [vault, writing-standard, glossary, layer/meta, topic/vault]
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# Glossary

This note is the controlled vocabulary of the vault. It gives **one approved term for each
thing**. The [[writing-standard]] requires these terms. The checker `_tools/ste-check.py` reads
the rules block at the end of this note and reports each forbidden term.

A forbidden term is permitted only inside `code`, because code shows a literal identifier.

## How to add a term

1. Search the vault for the names that people use for the thing.
2. Choose one name. Prefer the name that the live system uses.
3. Add a row: the approved term, its meaning, and the names not to use.
4. If an old name is common in the vault, add a rule to the block below.
5. Fix the old name in the live notes. Do not change records (journals, logs, history).

## The vault

| Approved term | Meaning | Do not use |
|---|---|---|
| **the vault** | This Obsidian knowledge base | the wiki, the KB repo, the docs |
| **note** | One markdown file in the vault | page, document (for a vault file) |
| **decision record** | A `D-NNN` note in `1-Executive/decisions/` | ADR (in new text) |
| **MCP server** | A server that gives tools to agents through the Model Context Protocol | MCP (alone, for the server), plugin |
| **work item** | An item in the team issue tracker | TODO, side quest, ticket (in the vault) |

## Environment

| Approved term | Meaning | Do not use |
|---|---|---|
| **<host-name>** | <what the host does> | <other names> |
| **<service-name>** | <what the service does> | <old names, nicknames> |

## Retired — do not describe as current

<List the systems and names that are retired. The checker gives a warning for these.>

## Rules for the checker

Each rule has a regular expression, the replacement and a severity. `tags: true` also checks
the frontmatter tags. `case: sensitive` makes the pattern case-sensitive.

```yaml ste-rules
forbidden:
  - {pattern: '\bthe wiki\b',     use: 'the vault', severity: warning}
  - {pattern: '\bADRs?\b',        use: 'decision record (D-NNN)', severity: warning, case: sensitive}
filler:
  - basically
  - simply
  - just
  - obviously
  - actually
  - really
  - quite
  - very
modal:
  - should
  - might
  - may
replace:
  - {pattern: '\bset ?up\b(?! *[:=])',  use: 'install, configure'}
  - {pattern: '\bspin(?:s|ning)? up\b', use: 'start'}
  - {pattern: '\bmake sure\b|\bensure\b', use: 'verify that, do a check'}
  - {pattern: '\bin order to\b',        use: 'to'}
  - {pattern: '\butili[sz]e\b|\bleverage\b', use: 'use'}
```

## Related

[[writing-standard]] · [[topics]] · [[AGENTS]]
