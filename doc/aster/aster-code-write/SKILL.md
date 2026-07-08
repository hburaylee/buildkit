---
name: aster-code-write
description: Write code guided by persona-keyed coding guidelines. Use when asked to implement a feature, fix a bug, or write new code.
---

# aster-code-write

Write code guided by persona-keyed coding guidelines.
Before writing a single line, this skill loads the relevant constraints from
each reviewer persona and designs against them — so the code satisfies correctness,
security, maintainability, hardware, and documentation concerns from the start.

## Interface

```
<spec-file> [--output <path>] [--guidelines <path>]
```

- `<spec-file>` — **required**, a Markdown file describing what to build.
  See below for the expected format.
- `--output <path>` — where to write the design rationale.
  Default: `<spec-file>.rationale.md`.
- `--guidelines <path>` — path to a directory of persona-keyed coding guidelines.
  Default: `coding-guidelines` (the `coding-guidelines` subdirectory of this skill).
  When provided, the skill reads project-specific rules from it.
  When omitted, it falls back to this default directory.

## Pipeline

### Phase 1 — Design

**1. Parse the spec.**

Extract from the spec file: what to build, target files/crates,
acceptance criteria, and any explicit constraints.

**2. Activate personas.**

Five personas exist. Three always activate on any code change;
two activate only when the task touches their remit:

| Persona | Activates |
|---|---|
| maintainability | Always |
| development | Always |
| security | Always |
| hardware | When the task touches assembly (`*.S`, `*.asm`), inline asm (`asm!`, `global_asm!`), or architecture-specific code |
| documentation | When the task touches user-facing docs, API surfaces, or compatibility files |

Activation is determined from the spec's target paths.
Do not use a model to triage — a wrongly-skipped persona is a missed constraint.

**3. Fan out design passes.**

Spawn one isolated pass per activated persona.
Each pass receives:
- The task spec
- That persona's file from this skill's `personas/` directory
- If `--guidelines` is given, the matching guideline file from that directory
  (defaults to `coding-guidelines` when the flag is omitted)
- Any relevant existing code for context

Each pass returns a structured constraint document
(see `personas/design_contract.md` for the schema).

File each output under a temp `<fragdir>/<persona>.json`.

**4. Synthesize.**

Merge the per-persona outputs into one design document:

- Group constraints by target file
- Resolve conflicts — safety/correctness override style.
  When neither is higher-priority, flag both for the human.
- Never silently drop a constraint.

Conflict rules:
1. Security / Hardware constraints override Maintainability
2. Development (correctness) constraints override Maintainability
3. Everything else — flag both, let the human decide

### Phase 2 — Implement

**5. Read context.**

Load the target files, their dependencies, and the synthesized constraints.

**6. Write code.**

For each constraint, either satisfy it or note in the rationale why it does not
apply. Never silently skip a constraint.

Work through each persona's checkpoint list below.

---

#### Maintainability checklist

Design shape, naming, layout, comments, commit hygiene.

- [ ] Each new type/function/module lives where it fits the existing structure
- [ ] The public API is minimal — only what callers need
- [ ] Every new public item has a descriptive, idiomatic name
  - No single-letter names except loop counters
  - No non-obvious abbreviations
  - `CamelCase` for types, `snake_case` for functions/variables, `SCREAMING_SNAKE_CASE` for constants
- [ ] Functions are small and single-purpose (prefer under ~50 lines)
- [ ] Visibility is as narrow as possible: private, then `pub(super)`, then `pub(crate)`, then `pub`
- [ ] Import order: std → external → crate → super → self
- [ ] Every public item has a doc comment (`///`) explaining what it does, not how
- [ ] Inline comments explain *why*, not *what* (the code already shows *what*)
- [ ] Commits are atomic — one logical change each
- [ ] Commit subjects use imperative mood ("Add X" not "Added X")
- [ ] If the work needs a preparatory refactor, it is a separate commit, first

#### Development checklist

Correctness, error handling, concurrency, efficiency, tests.

- [ ] Every code path returns the correct result
- [ ] Edge cases are handled: empty, full, zero, max, null-like values
- [ ] No reachable `unwrap`/`expect`/`panic!` — every fallible operation handles failure
- [ ] Errors are propagated (returned or wrapped), never silently swallowed
- [ ] Arithmetic that could overflow uses checked/wrapping/saturating operations explicitly
- [ ] Invariants that must hold are debug-asserted
- [ ] Every resource acquisition (lock, allocation, handle, timer, fd) is released via `Drop`, not a manual pair
  - A guard bound to a local and never used is dropped too early — bind it to a named variable
- [ ] If the new code takes multiple locks, their order matches the existing convention
- [ ] No I/O or blocking operations while holding a spinlock
- [ ] Check-then-act sequences on shared state re-validate after the act (TOCTOU)
- [ ] Lock-free data structures using atomics have explicit memory ordering, justified
- [ ] No linear scans on hot paths (scheduling, interrupt handling, I/O submission) unless unavoidable
- [ ] No unnecessary data copies on hot paths
- [ ] Logging uses appropriate levels: trace for per-event noise, debug for state transitions, info for significant events
- [ ] Tests cover: happy path, error paths, edge cases
- [ ] Tests exercise the public API, not internal state
- [ ] Tests clean up after themselves

#### Security checklist

Unsafe soundness, input validation, exploitable concurrency.

- [ ] Every `unsafe` block has a `// SAFETY:` comment that explains *why* the contained operations are sound
  - The justification must actually hold — not just stated, but true given the current invariants
- [ ] Every `unsafe fn` or `unsafe trait` has a `# Safety` doc section stating the caller's obligations
- [ ] `unsafe` code does not appear outside the crates permitted to use it
- [ ] The change does not weaken a safety invariant that existing `unsafe` code elsewhere depends on
  - In particular: changing a struct field's type, size, alignment, or visibility can break a distant `SAFETY` comment silently
- [ ] All data crossing a trust boundary (syscall args, user buffers, lengths, pointers) is validated at the boundary
  - Once validated, it is treated as trusted internally
  - A silent clamp or truncation that hides an error the contract requires reporting is a defect
- [ ] No use-after-free: memory is not accessed after it is freed
- [ ] No TOCTOU: shared state is not checked then used without re-validation

#### Hardware checklist (only when activated)

Assembly conventions, ABI invariants.

- [ ] New assembly is in the correct section with appropriate directives
- [ ] Instruction widths are explicit where size matters
- [ ] Assembly functions have correct visibility, type, and size annotations
- [ ] Labels follow the project's prefix convention
- [ ] Alignment uses `.balign` directives, not manual padding bytes
- [ ] On x86-64: `%rsp` is 16-byte aligned before every `call`
- [ ] Structs with hardware- or ABI-dictated layout (trap frames, register save areas, page table entries) have correct field sizes, offsets, and total size
  - A field reorder or padding change can silently break the ABI

#### Documentation checklist (only when activated)

Doc style, doc currency.

- [ ] New prose uses semantic line breaks — one sentence or clause per line
- [ ] If the change alters a user-facing API behavior, the matching docs are updated in the same change
- [ ] If the change adds or modifies a published crate, its `README.md` serves as crate-level documentation

---

**7. Write tests.**

Tests are not optional. For each test requirement from the Development design pass:
- Cover the happy path (expected inputs → expected outputs)
- Cover error paths (invalid inputs → correct errors)
- Cover edge cases (empty, full, boundary values)
- Use the public API; do not test private internals

**8. Write rationale.**

Produce `<output>`: a Markdown file recording:

```markdown
# Design Rationale: <task title>

## Activated Personas
- maintainability (always)
- development (always)
- security (always)
- hardware (activated: touches `arch/x86/...`)
- documentation (not activated)

## Key Design Decisions

### <decision title>
**Constraint:** <persona>/<rule> (<priority>)
**Decision:** <what was decided and why>
**Trade-off:** <what was given up, if anything>

## Constraint Status

| Persona | Constraint | Status |
|---|---|---|
| development | raii | ✓ satisfied — see `src/foo.rs:30` |
| security | validate-at-boundaries | ✓ satisfied — see `src/syscall.rs:15` |
| maintainability | descriptive-names | ✓ satisfied |
| ... | ... | ... |

## Dismissed Constraints

| Persona | Constraint | Reason |
|---|---|---|
| hardware | 16b-align-rsp | Not applicable — no new call instructions |
```
