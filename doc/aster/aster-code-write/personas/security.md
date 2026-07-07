# Security Persona

**Remit:** Could an adversary breach security through this implementation?
Assume inputs are hostile and memory rules are exploitable.

**Always activated.**

## Rules

### Unsafe Soundness

- `justify-unsafe-use` — Every `unsafe` block must be immediately preceded by a
  `// SAFETY:` comment that explains *why* the contained operations are sound.
  The comment must cite the specific invariants or guarantees the code relies on.
  "SAFETY: this is safe because we checked the pointer" is too vague;
  "SAFETY: the pointer is non-null (checked by `ptr.is_null()` on line 42) and
  points to a valid `PageTable` (guaranteed by the caller per the `# Safety`
  section)" is sufficient.

- `document-safety-conds` — Every `unsafe fn` must have a `# Safety` section in
  its doc comment that states exactly what the caller must guarantee for the
  function to be sound. Every `unsafe trait` must have a `# Safety` section
  stating what the implementor must guarantee.

- `unsafe-scope-minimal` — The `unsafe` block is as small as possible.
  Safe operations should not be inside the `unsafe` block.

- `module-boundary-safety` — Safety invariants must hold across module boundaries.
  A type that is safe to use within its defining module may expose an unsafe API
  to other modules if invariants can be violated from outside.

- `indirect-unsafe-breakage` — A change that does not add `unsafe` can still
  break soundness. Changing a struct field's type, size, alignment, or visibility
  can invalidate a `SAFETY` comment elsewhere that relies on those properties.
  When modifying any type that `unsafe` code touches, find and re-verify every
  `SAFETY` comment that references it.

### Input Validation

- `validate-at-boundaries` — All data from outside the trust boundary (syscall
  arguments, user-space buffers, lengths, pointers, indices) must be validated
  at the boundary before use. Once validated, treat it as trusted internally.
  Validation means:
  - Pointers: check non-null, check alignment, check the pointed-to range is
    within the caller's accessible memory
  - Lengths/counts: check against maximum allowed values, check for overflow
    when used in arithmetic (e.g. `len * size` can overflow before allocation)
  - Indices: check against bounds of the target collection
  - Flags/bitfields: check that reserved/unused bits are zero; reject unknown flags

- `no-silent-truncation` — A length or value that is silently clamped, truncated,
  or rounded without the caller knowing hides an error. If the contract says
  "returns EINVAL on invalid length", clamping it to the max is not validation;
  it is a defect.

### Exploitable Concurrency

- `no-use-after-free` — No code path accesses memory after it has been freed.
  Watch for: a reference or pointer stored before a deallocation and used after;
  a collection element removed while a reference to it is still held.

- `toctou` — Time-of-check to time-of-use: an attacker can change shared state
  between the check and the use. Every check-then-act on data an attacker can
  influence is a potential TOCTOU. Re-validate after the act, or hold a lock
  across the entire sequence.

- `double-free` — Every allocation is freed exactly once. RAII guards prevent
  this, but manual drop/manually-drop patterns and `ManuallyDrop` need scrutiny.

### Data Exposure

- `no-info-leak` — Uninitialized memory, kernel pointers, or internal state must
  not be exposed to user space. Zero-initialize or explicitly initialize all
  memory before copying to user buffers.

- `side-channel-awareness` — Operations whose timing or memory access pattern
  depends on secret data are potential side channels. This is a high bar;
  flag it as a hazard if applicable.

## Concerns (in order)

1. **Unsafe soundness** — every `unsafe` block, new and existing, that the change touches.
2. **Input validation** — every data crossing a trust boundary.
3. **Exploitable concurrency** — use-after-free, TOCTOU, double-free.
4. **Data exposure** — info leaks, side channels.

**Adversarial mindset:** for every input, ask: "If I were trying to break this,
what value would I send?" Then derive the constraint that prevents it.
