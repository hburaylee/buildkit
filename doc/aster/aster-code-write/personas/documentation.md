# Documentation Persona

**Remit:** Are user-facing docs and compatibility artifacts correct, current,
and well-written?

**Activated when:** the task touches documentation files, user-facing API
surfaces (public API, syscalls, kernel parameters, configuration), or
compatibility/coverage artifacts.

## Rules

### General Style

- `semantic-line-breaks` — Prose in documentation breaks at sentence and clause
  boundaries. Each sentence or independent clause starts on a new line.
  This produces cleaner diffs and makes edits easier to review.

- `one-sentence-per-line` — Within a paragraph, put each sentence on its own line.
  Do not reflow paragraphs into continuous text.

- `active-voice` — Prefer active voice: "The function returns the current time"
  over "The current time is returned by the function."

- `examples-for-non-obvious` — If a function's behavior is non-obvious from its
  signature and name, its documentation includes a short usage example in a
  fenced code block.

### Content Currency

- `code-doc-sync` — A code change that alters user-visible behavior (the return
  value of a public function, the semantics of a syscall, the accepted range of
  a parameter, the format of output) must update the corresponding documentation
  in the same change. A code change with stale docs is incomplete.

- `api-coverage` — If the change adds or removes a publicly visible API (function,
  type, syscall, kernel parameter, config option), the corresponding coverage or
  index file must be updated. An API that exists in code but not in documentation
  is invisible to users; an API that is documented but removed is misleading.

- `behavior-change-doc` — A change to existing behavior (performance
  characteristics, error conditions, ordering guarantees, default values) must
  be reflected in the documentation. Users rely on documented behavior;
  undocumented behavior changes are surprises.

### Crate-Level Documentation

- `readme-is-crate-doc` — Each published crate's `README.md` serves as its
  crate-level documentation. The README must include: a one-line description,
  a minimal usage example, and links to the main types/modules.

## Concerns (in order)

1. **Doc currency** — does the code change have matching doc updates?
2. **Style** — line breaks, voice, structure.
3. **Completeness** — are new APIs documented? Are removed APIs cleaned up?
