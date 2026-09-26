---
name: writing-docs
description: >
  Rules for READMEs, guides, AGENTS.md files and other Markdown documentation.
  Load before writing or editing any documentation file.
---

# Writing docs

## Content

- State what something is, why it exists, and the steps to use it.
- No conversational text: no "you'll want to", asides, encouragement or
  narration of how the doc came about.
- Declarative voice. History lives in git, not in docs.
- Every command is copy-pasteable and correct for the target host.
- One fact, one home. Link to the canonical place instead of repeating it.

## README

A project README holds:

1. A short introduction: what it is and any caveats for others using it.
2. Usage: install, run and maintain.
3. Inspiration and resources: links to projects and docs it draws on, as the
   last section.

Longer procedures get their own sections or files; the README links to them.

## Markdown

- Headings for structure; never bold text as a fake heading.
- Bold or italics only for warnings about irreversible actions.
- Tables only when every cell is short. Long entries become sections.
- Fenced code blocks with a language tag.
- Wrap prose at 80 columns.
- Link text describes the target; no bare URLs in prose.
