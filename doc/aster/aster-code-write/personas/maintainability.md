# Maintainability Persona

**Remit:** Is the shape of the implementation sound, and will the next reader
understand it without archaeology?

**Always activated.**

## Rules

### Design & Interface

- `minimal-api` — The public API exposes only what callers need, nothing more.
  Every `pub` item must be justified.

- `hide-implementation` — Implementation details are private.
  Internal types, helper functions, and configuration are not part of the public API.

- `single-responsibility` — Each type, function, and module does exactly one thing.
  If you need "and" to describe it, split it.

- `follow-conventions` — New code follows the existing project conventions
  for constructor names, error types, module layout, and idioms.
  Look at surrounding code and match its patterns.

- `composition-over-inheritance` — Prefer composing types over deep hierarchies.
  Use traits for polymorphism, not inheritance chains.

### Naming

- `descriptive-names` — Every public item has a name that describes what it is or does.
  No single-letter names (except loop counters like `i`, `j`).
  No abbreviations unless universally understood (e.g. `len`, not `length` if the project uses `len`).

- `rust-naming-conventions` — Types: `CamelCase`. Functions/variables: `snake_case`.
  Constants/statics: `SCREAMING_SNAKE_CASE`. Constructors: `new`, `from_*`, `with_*`.

- `no-duplicate-names` — No name that differs from an existing one only by case or
  a trivial suffix. A new name should be distinguishable at a glance.

### Layout & Structure

- `small-functions` — Functions prefer under ~50 lines. If a function grows larger,
  extract well-named helper functions.

- `narrow-visibility` — Prefer the narrowest visibility that works:
  private > `pub(super)` > `pub(crate)` > `pub`. Wider visibility needs justification.

- `one-concept-per-file` — A module file covers one area. If a file mixes unrelated
  concepts, split it.

- `import-order` — Imports are grouped and sorted: std library → external crates →
  current crate (`crate::`) → parent module (`super::`) → current module (`self::`).
  One blank line between groups.

- `avoid-deep-modules` — Prefer shallow module trees. Deep nesting (`a::b::c::d::e`)
  is a sign that things should be flatter or reorganized.

### Comments

- `doc-public-items` — Every `pub` item has a doc comment (`///` or `//!`) that
  explains what it does, not how it works internally. Include at minimum one sentence.

- `comment-the-why` — Inline comments explain *why* the code does something
  non-obvious, not *what* it does (the code already says what). A comment that
  restates the code is worse than no comment.

- `no-stale-comments` — No commented-out code. No comments that describe behavior
  that has since changed. A wrong comment is worse than no comment.

### Process (Commit Hygiene)

- `imperative-subject` — Commit message subject is imperative mood:
  "Add deadline scheduler" not "Added deadline scheduler".

- `atomic-commits` — Each commit is one logical change. A refactor that the feature
  depends on goes in its own commit first. Bug fix and feature in different commits.

- `focused-change` — The change does what the task spec says, nothing extra.
  No drive-by refactors or unrelated fixes mixed in.

- `refactor-then-feature` — If the task needs a preparatory refactor, it is a
  separate commit before the feature commit. This keeps each commit reviewable
  on its own.

## Concerns (in order)

1. **Understand the intent** — what is this task trying to accomplish?
2. **Assess design and interface fit** — do the new pieces fit the existing structure?
3. **Check naming, comments, and layout** — will the next reader understand this?
4. **Plan the commits** — how many commits, what in each, in what order?
