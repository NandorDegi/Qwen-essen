---
title: Writing standard — STE-based technical English
tags: [vault, writing-standard, ste, layer/meta, topic/vault]
created: 2026-10-29
updated: 2026-10-29
---

# Writing standard

This vault uses a writing standard that is based on **ASD-STE100 Simplified Technical English
(STE)**. STE is the controlled language of aerospace maintenance manuals. Its rules make text
clear for readers who use English as a second language, and for AI agents. Each layer uses a
different level of the standard.

We use the STE writing rules and our own controlled vocabulary in [[glossary]]. We do not claim
compliance with the STE dictionary. The correct term is "STE-based", not "STE-compliant".

## Which rules apply to which layer

| Layer | Standard | Checker mode |
|---|---|---|
| `3-Technical/` and `AGENTS.md` | Strict STE. Procedures: 20 words maximum per sentence. Descriptive text: 25 words maximum | `technical` |
| `2-Architecture/` | STE writing rules. 25 words maximum per sentence. Technical names are permitted | `architecture` |
| `1-Executive/` | Plain business English. Short sentences, one term for one thing, no jargon | `executive` |
| `0-Meta/` | Plain English | `meta` |
| Journals, `log.md`, session logs, dated history sections | Do not rewrite. They are a record | not checked |

## Words

1. Use **one term for one thing**. Use the approved term from [[glossary]].
2. Use each word with **one meaning** only. For example, "the vault" is this knowledge base. Give the password store a different name.
3. **Technical names** are permitted: product names, host names, commands, ports, paths and protocols. Write commands, paths and identifiers in `code`.
4. Do not use more than **three nouns in a row**.
5. Do not use filler words: basically, simply, just, obviously, actually, very, quite, really.
6. Use "must" for a requirement and "can" for a possibility. Do not use "should", "may" or "might" in an instruction.

| Bad | Good |
|---|---|
| Restart the gateway service config reload handler. | Restart the handler that reloads the configuration of the gateway. |
| You should just restart the broker. | Restart the broker. |
| The historian, the data store and the archive all keep the values. (three names for one thing) | The historian keeps the values. |

## Verbs

7. Use the **active voice**. You can use the passive voice in a description if the agent is not known.
8. Use **simple tenses**: present, past and future.
9. Do not use an *-ing* word as a noun or as an adjective. Technical names with *-ing* are permitted.
10. In an instruction, use the **imperative**.

| Bad | Good |
|---|---|
| The stack is deployed by the container manager. | The container manager deploys the stack. |
| Restarting the service clears the cache. | When you restart the service, it clears the cache. |
| The next step would be to check the logs. | Read the logs. |

## Sentences

11. **Procedures:** 20 words maximum per sentence. **Descriptive text:** 25 words maximum.
12. Write **one instruction per sentence**. Two actions in one sentence are permitted only if you do them at the same time.
13. Put a **condition before the instruction**.
14. Do not use a semicolon. Write two sentences, or use a list.
15. Do not leave out "the", "a" or "an".

| Bad | Good |
|---|---|
| Stop the stack if the plan shows a recreate. | If the plan shows a recreate, stop the stack. |
| Open the console, find the tag and change its value. | 1. Open the console. 2. Find the tag. 3. Change its value. |
| Check config; restart. | Check the configuration. Then restart the service. |

## Procedures

16. Write the steps in the **order of work**, as a numbered list.
17. Put each **warning and caution before** the step that it applies to.
    - **Warning:** a risk of data loss, an outage or a security incident.
    - **Caution:** a risk of a degraded state or of extra work.
18. Start a warning with a clear command. Then give the risk.
19. After a step that changes the system, tell the reader how to **verify** the result.

**Bad:**

> 3. Run `compose up -d`. (Be careful, this can wipe the database password.)

**Good:**

> **Warning:** Do not run `compose up -d` directly. A direct `up` can recreate the database container with an incorrect password.
>
> 3. Deploy the stack from the container manager.
> 4. Verify that the container ID changed: `docker ps --filter name=db`.

## Descriptive text

20. Put the most important information **first**.
21. Write **one topic per paragraph**, and 6 sentences maximum per paragraph.
22. Give a **date** with every measured fact: "(verified 2026-10-29)".

| Bad | Good |
|---|---|
| The broker currently handles about 250 topics. | The broker carries 246 topics (verified 2026-10-29, `topic list` count). |
| Recently we moved the historian. | The historian moved to the new host on 2026-10-14. |

## Common replacements

| Do not write | Write |
|---|---|
| set up, spin up | install, configure, start |
| make sure, ensure | verify that, do a check |
| in order to | to |
| utilize, leverage | use |
| a number of | some, or give the number |
| it is recommended that you | do this |
| should | must, or can |

## A full example

**Before (not STE):**

> Basically, you'll want to make sure the collector is restarted after changing its config,
> since otherwise it may keep running the old demo settings which were baked into the image.

**After (STE):**

> Restart the collector after you change its configuration. If you do not restart it, it
> continues to use the demo configuration from the image.

## The checker

Run `python3 _tools/ste-check.py <note>.md` on each note that you change. Run it with no file
to check the full vault. Fix all errors before you commit. A warning is advisory. The checker
reads the forbidden terms from the `ste-rules` block in [[glossary]].

## Related

[[glossary]] · [[AGENTS]] · [[topics]]
