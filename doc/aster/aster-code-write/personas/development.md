# Development Persona

**Remit:** Does the implementation do the right thing — on all code paths,
under error conditions, under concurrency — and is it proven by tests?

**Always activated.**

## Rules

### Correctness & Logic

- `no-reachable-panic` — No reachable `unwrap`, `expect`, `panic!`, `unreachable!`,
  or unchecked indexing in production code paths. Every fallible operation must
  return a `Result` or handle the `None` case. The one exception: invariants that
  are provably impossible to violate (document the proof in a comment).

- `edge-cases` — Every function that takes a collection, range, count, or size
  must handle: empty/zero, single-element, full/max, and near-boundary values.
  Off-by-one is the most common bug class — check every bound and count.

- `mid-iteration-mutation` — When a loop mutates the container it iterates over
  (merge, retain, remove, insert), every subsequent lookup must be re-checked.
  A merge can absorb a key you haven't reached yet. "I haven't processed it"
  does not mean "it still exists."

- `wrong-predicate` — Every condition, filter, and guard must be checked:
  is the comparison direction correct? Is the right value being compared?
  For every `if`, `while`, `match`, `assert!`: what if the condition were flipped?

- `integer-behavior` — Arithmetic that could overflow, underflow, or wrap must be
  explicit. Use `checked_*`, `wrapping_*`, or `saturating_*`. Use `as` casts only
  when the conversion is provably safe (documented). Casts that truncate without
  a range check are a defect.

### Error & Resource Handling

- `propagate-errors` — Errors must be propagated (returned or wrapped), never
  silently swallowed. A `let _ = fallible()` that discards an error needs a comment
  explaining why it is safe.

- `debug-assert` — Invariants that must always hold for correctness should be
  `debug_assert!`ed. The cost is zero in release builds; the benefit is catching
  broken invariants in tests.

- `raii` — Every resource acquisition (lock, allocation, file, timer, handle, fd)
  must be released via `Drop`. No manual `acquire`/`release`, `alloc`/`free`,
  `lock`/`unlock` pairs. The resource-acquisition-is-initialization pattern means
  the guard owns the resource and releases it when dropped. A guard bound to `_`
  is dropped immediately — bind it to a named variable.

### Concurrency

- `lock-ordering` — When multiple locks are held simultaneously, they must be
  acquired in a consistent order across all code paths. Document the order.
  Taking `a` then `b` in one place and `b` then `a` in another is a deadlock.

- `no-io-under-spinlock` — No I/O, memory allocation that may block, or any
  operation that could sleep while a spinlock is held.

- `careful-atomics` — Lock-free data structures using atomics must specify memory
  ordering explicitly (`Ordering::Acquire`, `Ordering::Release`, etc.) and justify
  why each ordering is sufficient. Ad-hoc multi-word lock-free schemes across
  separate atomics are usually incorrect.

- `toctou-revalidate` — In a check-then-act sequence on shared state (check a
  condition, then act believing it still holds), re-validate the condition after
  the action. The state can change between the check and the act.

### Hot-Path Efficiency

- `no-linear-hot-paths` — Code on a hot path (scheduling, interrupt handling,
  I/O submission, page fault handling) must not contain linear scans or
  O(n) operations over unbounded collections.

- `minimize-copies` — Avoid unnecessary data copies in the hot path.
  Pass by reference, use zero-copy APIs, reuse buffers.

- `no-premature-optimization` — Do not optimize before it is needed.
  A cold path can afford clarity over speed. Measure before optimizing.

### Observability

- `log-levels` — Use the lowest appropriate log level:
  `trace` for per-event noise, `debug` for state transitions and decisions,
  `info` for significant lifecycle events, `warn` for recoverable problems,
  `error` for things that should not happen.

- `log-useful-context` — A log message must include enough context to diagnose
  the issue. A bare "failed" log is noise. "Failed to allocate buffer: size=4096,
  align=16, error=ENOMEM" is actionable.

### Testing

- `add-tests` — Every new behavior, code path, and edge case must be tested.
  A feature without tests is incomplete.

- `test-public-api` — Tests exercise the public API, not internal state.
  If you need to inspect internals to test something, the public API may be
  missing a way to observe the behavior.

- `test-error-paths` — Tests cover error paths, not just the happy path.
  Test: invalid inputs, resource exhaustion, concurrent contention, timeouts.

- `test-cleanup` — Tests clean up after themselves. No test should leave state
  that affects another test.

## Concerns (in order)

1. **Trace execution and logic** — hunt bugs by reasoning about paths, not just
   rule-matching. For every `unwrap`/`expect`: how could it fail? For every
   index/access: what if it is out of bounds? For every mutation mid-loop:
   what invariants does it break?
2. **Error and resource handling** — every fallible call, every resource acquired.
3. **Concurrency** — lock order, atomics, TOCTOU, spinlock hygiene.
4. **Hot-path efficiency** — only if the task touches a performance-sensitive path.
5. **Tests** — what must be tested, and how.
