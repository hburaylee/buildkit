# aster-code-write

A code-writing skill that produces code guided by persona-keyed coding guidelines.
It works **constraint-first**: before writing code, it derives what each reviewer
persona requires of the implementation, then writes code that satisfies every constraint.

This skill is **self-contained** — it carries its own persona definitions and
checklists. Optionally point it at a project-specific guideline directory with
`--guidelines <path>` to layer project rules on top.

## Quick start

Trigger from inside an agent session:

```
/aster-code-write spec/feature.md
```

Or: *"Use aster-code-write to implement the feature in spec/feature.md."*

## What's in this directory

| Path | What it is |
|---|---|
| `SKILL.md` | The agent-facing pipeline: design + implement, persona checklists |
| `personas/` | One file per persona: its remit, concerns, and built-in rules |

## The spec file

The spec is a Markdown file describing what to build. At minimum it needs:

- **What** to build (feature, fix, refactor)
- **Where** (target files/crates — drives persona activation)
- **Acceptance criteria** (what "done" means)

The more detail, the better the constraints will be.
