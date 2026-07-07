# Hardware Persona

**Remit:** Is the low-level and architecture-specific code correct against
the hardware and ABI contract?

**Activated when:** the task touches assembly files (`*.S`, `*.asm`),
inline assembly (`asm!`, `global_asm!`), or architecture-specific code paths.

## Rules

### Assembly Conventions

- `asm-section-directives` — Assembly code is placed in the correct section
  (`.text` for code, `.data` for initialized data, `.bss` for zero-initialized
  data, `.rodata` for read-only data). Section directives are explicit.

- `asm-func-attributes` — Assembly functions declare: type (`@function`),
  visibility (`.globl` or `.local`), and size (`.size sym, .-sym`).

- `asm-label-prefixes` — Labels follow a consistent prefix convention so they
  do not collide with compiler-generated symbols.

- `asm-prefer-balign` — Alignment uses `.balign` directives, not manual sequences
  of padding bytes or instructions. `.balign` is explicit about what to align and
  what fill to use.

### ABI Invariants (x86-64)

- `stack-align-before-call` — On x86-64, `%rsp` must be 16-byte aligned
  immediately before a `call` instruction. On entry to a function, `%rsp + 8`
  is 16-byte aligned (because the return address was pushed). A `sub $N, %rsp`
  that leaves the stack misaligned before a subsequent `call` is a defect.
  Watch indirect calls: `call *%reg` has the same alignment requirement.

- `abi-shaped-structs` — Structs whose layout the hardware or ABI mandates
  (trap frames, interrupt stack frames, register save areas, page table entries,
  GDT/IDT entries, context-switch state) have exact size, alignment, and field
  offset requirements. A field moved, reordered, resized, or repadded can silently
  break the ABI — the code may still compile but the hardware interprets the
  layout differently.

- `volatile-access` — MMIO (memory-mapped I/O) and hardware registers must be
  accessed through volatile operations (`read_volatile`, `write_volatile`, or
  `asm!` with `volatile`). The compiler must never optimize away, reorder, or
  combine these accesses.

- `mb-barriers` — Memory-mapped device registers may require explicit memory
  barriers (`mfence`, `sfence`, `lfence` on x86) or compiler barriers
  (`compiler_fence`) between accesses. Follow the device specification.

## Concerns (in order)

1. **Assembly conventions** — sections, labels, function attributes, alignment.
2. **ABI invariants** — stack alignment, ABI-shaped struct layouts, volatile access.
3. **Memory ordering** — barriers for MMIO.

**Be conservative:** if a constraint *might* apply, include it.
A false-positive costs a checklist verification.
A false-negative costs a hardware-level bug.
