---
title: Migration — bring an old vault up to the standard
tags: [vault, runbook, migration, layer/meta, topic/vault]
created: 2026-10-29
updated: 2026-10-29
---

# Migration — bring an old vault up to the standard

Do this procedure on the first run, before other work. The vault came from an old export.
Many notes are out of date, and many do not follow the rules in [[AGENTS]]. Work in small
batches. Add one log entry for each batch.

## Rules for the full migration

- Do a maximum of 10 notes in one batch.
- Do not delete a fact that you cannot verify. Mark it instead: "(not verified since YYYY-MM-DD)".
- Do not rewrite journals, session logs, history sections or old `log.md` entries. Fix only their frontmatter.
- Do not invent a fact to fill a gap. Ask a person, or record the gap in your report.
- Do not change the name of a note unless it is necessary. A new name breaks the links to it.
- If a person edits the vault at the same time, read each note again before you change it.

## Stage 0 — Install the kit

1. Copy `writing-standard.md` to `0-Meta/writing-standard.md`.
2. Copy `templates/glossary.md` to `0-Meta/glossary.md`.
3. Copy `templates/topics.md` to `0-Meta/topics.md`.
4. Copy the other files in `templates/` to `_templates/`.
5. Copy `ste-check.py` to `_tools/ste-check.py`.
6. Copy `KB-AGENT-PROMPT.md` to `AGENTS.md` in the vault root.

**Caution:** If one of these files exists, do not replace it. Read it first. Move its useful content into the new file, then replace it.

7. If a `log.md` does not exist in the vault root, make one with the frontmatter and the H1 `# Log`.
8. Verify the result: run `python3 _tools/ste-check.py AGENTS.md`. Expect 0 errors.

## Stage 1 — Audit, and change nothing

1. List each note in the vault with its folder, its tags and its `updated:` date.
2. For each note, record these findings:
   - The layer tag is missing, or it does not agree with the folder.
   - The topic tag is missing, or there is more than one.
   - The `updated:` date is missing.
   - The note is in a folder that is not one of the four layers.
   - The note has the same subject as a different note.
   - A link in the note points to a note that does not exist.
   - The note contains a TODO list, a backlog or a secret value.
3. Count the checker errors for each note: `python3 _tools/ste-check.py --summary`.
4. Write the findings in `0-Meta/migration-audit.md`, as one table with one row for each note.
5. Add a log entry: `## [YYYY-MM-DD HH:MM] migrate | audit`. Give the counts of each finding.
6. Show the audit to a person. Continue only after the person agrees with the plan.

**Warning:** If a note contains a secret value, stop the migration. Tell a person immediately. Remove the value only when the person agrees. The value stays in git history, so the person must also change the secret.

## Stage 2 — Choose the topics

1. Read the topic suggestions in `0-Meta/topics.md`.
2. Group the notes by subject, with the audit table and the links between the notes.
3. Write a set of 10 to 20 topics that fits the groups.
4. Write a decision record for the topic set. Use `_templates/decision-record.md`.
5. Replace the example rows in `0-Meta/topics.md` with the set.
6. Add a log entry: `## [YYYY-MM-DD HH:MM] decision | topic set`.

## Stage 3 — Fix the folders and the frontmatter

Do this stage in batches of 10 notes. Start with the notes that people read most.

1. For each note, decide its layer from the placement table in [[AGENTS]].
2. If the note is in the wrong folder, move it to the correct layer.
3. Add or fix the frontmatter: `title`, one `layer/*` tag, one `topic/*` tag, `created`, `updated`.
4. If `created` is not known, use the date of the first commit of the note, or the export date.
5. Set `updated` to the date of your change.
6. Verify the result: each link to a moved note must still resolve.
7. Add a log entry: `## [YYYY-MM-DD HH:MM] migrate | frontmatter batch N`. List the notes.

## Stage 4 — Merge and split

Do this stage in batches of 3 to 5 subjects.

1. For each group of notes with one subject, choose the note to keep. Keep the note with the most links to it.
2. Move each true fact from the other notes into the kept note.
3. Retire the other notes. Use the procedure in [[AGENTS]], section "Retire a note".
4. For each note that has more than approximately 200 lines and many subjects, split it into a hub and parts.
5. If a note covers two layers, split it. Put the stable part one layer up and the procedure one layer down.
6. For each decision that you find in a note, write a decision record and add it to the index.
7. Move each TODO list or backlog to the team issue tracker. Then remove it from the note.
8. Add a log entry for each batch: `## [YYYY-MM-DD HH:MM] migrate | merge batch N`.

## Stage 5 — Make the facts current

Do this stage in batches of 10 notes, by topic.

1. For each fact about the live environment, find a current source.
   A source is a live system, a person or a recent commit.
2. If the fact is still true, add the date: "(verified YYYY-MM-DD)".
3. If the fact is false, change it in place. Give the new date and the source.
4. If you cannot verify the fact, mark it: "(not verified since YYYY-MM-DD)".
5. Use read-only tools only. Do not change a live system to verify a note.
6. Add a log entry for each batch: `## [YYYY-MM-DD HH:MM] discover | topic <name>`.

## Stage 6 — Apply the writing standard

1. Run `python3 _tools/ste-check.py --summary --errors-only`.
2. Fix the notes with the most errors first, in batches of 10.
3. Use the approved terms. Add each new term to `0-Meta/glossary.md`.
4. Do not change the meaning of a sentence to satisfy the checker.
5. Add a log entry for each batch: `## [YYYY-MM-DD HH:MM] lint | STE batch N`.

## Stage 7 — Update the meta notes

1. Update `HOME.md` so that each link resolves to a live note.
2. Update the notes in `0-Meta/` that describe the vault and the direction of the team.
3. Delete `0-Meta/migration-audit.md`, or mark it complete with the date.
4. Run the checker on the full vault. Record the counts of errors and warnings.
5. Add a log entry: `## [YYYY-MM-DD HH:MM] migrate | complete`. Give the counts.

## Related

[[AGENTS]] · [[writing-standard]] · [[glossary]] · [[topics]]
