# For Maintainability

# 可维护性指南

*Is the shape of the change sound, and will the next reader understand it without archaeology?*

*变更的形态是否合理？下一位读者能否不靠考古就理解它？*

This is the index of the **maintainability** guidelines.
Each subsection is its own page,
and each entry below links a stable `short-name` to its guideline,
with a one-line gist so a reader (or a review tool) can grasp the guideline before opening it.

这是 **可维护性** 指南的索引。
每个小节都是独立页面，
下面的条目将稳定的 `短名称` 链接到对应指南，
并附上一行摘要，方便读者（或审查工具）在打开前先了解要点。

## Index

## 索引

**[Design](design.md)**

**[设计](design.md)**

- [`single-responsibility`](design.md#single-responsibility): Each module, type, or function has one reason to change; keep functions small and one concept per file.

- [`single-responsibility`](design.md#single-responsibility)：单一职责：每个模块、类型或函数只有一个变更理由；保持函数短小，每个文件只承载一个概念。

- [`dry`](design.md#dry): Give every piece of knowledge a single representation; eliminate duplication once a pattern recurs.

- [`dry`](design.md#dry)：不要重复自己：让每份知识只有单一表示；一旦模式重复出现就消除重复。

- [`information-hiding`](design.md#information-hiding): Hide details behind interfaces; expose only what consumers need.

- [`information-hiding`](design.md#information-hiding)：信息隐藏：把细节隐藏在接口后面；只暴露消费者需要的内容。

- [`open-closed`](design.md#open-closed): Extend stable modules through existing interfaces; don't add extension points preemptively.

- [`open-closed`](design.md#open-closed)：开闭原则：通过已有接口扩展稳定模块；不要预先添加扩展点。

- [`least-surprise`](design.md#least-surprise): Names, types, and APIs behave as they suggest; prefer conventions users already know from Rust and Linux.

- [`least-surprise`](design.md#least-surprise)：最少惊讶：名称、类型和 API 的行为应与其暗示一致；优先采用 Rust 与 Linux 中用户已熟悉的约定。

- [`coupling-cohesion`](design.md#coupling-cohesion): Keep inter-module connections small and visible; keep each module focused on one purpose.

- [`coupling-cohesion`](design.md#coupling-cohesion)：耦合与内聚：模块间连接保持小而可见；每个模块专注于一个目的。

- [`consistency`](design.md#consistency): Do similar things the same way; follow an existing convention rather than coining a competing one.

- [`consistency`](design.md#consistency)：一致性：相似的事情用相同方式做；遵循已有约定，而非自创竞争约定。

- [`rust-native`](design.md#rust-native): Learn from Linux's design, not its C idioms; write idiomatic Rust.

- [`rust-native`](design.md#rust-native)：原生 Rust：从 Linux 的设计中学习，而非其 C 惯用法；编写地道的 Rust。

**[Process](process.md)**

**[流程](process.md)**

- [`imperative-subject`](process.md#imperative-subject): Write each commit subject in the imperative mood, ≤72 chars, verb-first ("Fix", "Add", "Remove"); backtick identifiers.

- [`imperative-subject`](process.md#imperative-subject)：祈使语气主题：提交主题使用祈使语气，≤72 字符，动词开头（“Fix”“Add”“Remove”）；标识符用反引号。

- [`atomic-commits`](process.md#atomic-commits): One logical change per commit; don't mix unrelated changes.

- [`atomic-commits`](process.md#atomic-commits)：原子提交：每次提交只包含一个逻辑变更；不要混入无关变更。

- [`refactor-then-feature`](process.md#refactor-then-feature): Put preparatory refactoring in its own earlier commit(s), separate from the feature.

- [`refactor-then-feature`](process.md#refactor-then-feature)：先重构再功能：把准备性重构放在独立的更早提交中，与功能变更分开。

- [`focused-prs`](process.md#focused-prs): Keep a PR on a single topic; ensure CI passes before requesting review.

- [`focused-prs`](process.md#focused-prs)：聚焦的 PR：PR 保持单一主题；请求审查前确保 CI 通过。

**[Naming](naming.md)**

**[命名](naming.md)**

- [`descriptive-names`](naming.md#descriptive-names): Names convey meaning at the point of use; avoid single letters and ambiguous abbreviations.

- [`descriptive-names`](naming.md#descriptive-names)：描述性名称：名称在使用处传达含义；避免单字母和模糊缩写。

- [`accurate-names`](naming.md#accurate-names): Avoid names that mislead about meaning, behavior, or side effects.

- [`accurate-names`](naming.md#accurate-names)：准确名称：避免名称对含义、行为或副作用产生误导。

- [`no-magic-number`](naming.md#no-magic-number): Give semantic names to numbers that encode rules, limits, units, masks, or external constants.

- [`no-magic-number`](naming.md#no-magic-number)：杜绝魔法数字：给编码规则、限制、单位、掩码或外部常量的数字起语义化名称。

- [`encode-units`](naming.md#encode-units): When the type doesn't carry the unit, put it in the name (`timeout_ns`, `size_pages`).

- [`encode-units`](naming.md#encode-units)：编码单位：当类型本身不携带单位时，把单位放进名称（`timeout_ns`、`size_pages`）。

- [`bool-names`](naming.md#bool-names): Name booleans as positive assertions (`is_`/`has_`/`can_`/…); avoid negation.

- [`bool-names`](naming.md#bool-names)：布尔命名：布尔值命名为正断言（`is_`/`has_`/`can_`/…）；避免否定。

- [`error-message-format`](naming.md#error-message-format): Lowercase start (unless a proper noun), specific, Linux man-page style for syscall errors.

- [`error-message-format`](naming.md#error-message-format)：错误信息格式：以小写开头（专有名词除外），具体明确，采用 Linux man 页风格描述系统调用错误。

**[Layout](layout.md)**

**[布局](layout.md)**

- [`top-down-reading`](layout.md#top-down-reading): Order a file top-down: entry points and core flow first, detail below.

- [`top-down-reading`](layout.md#top-down-reading)：自上而下阅读：文件按自上而下顺序排列：入口点和核心流程在前，细节在后。

- [`logical-paragraphs`](layout.md#logical-paragraphs): Group related statements into blank-line-separated paragraphs, each one sub-step.

- [`logical-paragraphs`](layout.md#logical-paragraphs)：逻辑段落：把相关语句用空行分成逻辑段落，每个段落对应一个子步骤。

**[Comments](comments.md)**

**[注释](comments.md)**

- [`explain-why`](comments.md#explain-why): Comments explain intent (why), not what the code does; if you must explain "what", rewrite the code.

- [`explain-why`](comments.md#explain-why)：解释为什么：注释解释意图（为什么），而不是代码在做什么；如果必须解释“做什么”，就重写代码。

- [`design-decisions`](comments.md#design-decisions): Document non-obvious choices, with rationale and alternatives considered.

- [`design-decisions`](comments.md#design-decisions)：设计决策：记录非显而易见的选择，附上理由和考虑过的替代方案。

- [`cite-sources`](comments.md#cite-sources): Cite the source (POSIX, Linux man page, hardware manual, paper) for spec/algorithm behavior.

- [`cite-sources`](comments.md#cite-sources)：引用来源：为规范/算法行为引用来源（POSIX、Linux man 页、硬件手册、论文等）。

**[Rust-Specific](rust-specific/)**

**[Rust 特定](rust-specific/)**

- [Naming](rust-specific/naming.md)

- [命名](rust-specific/naming.md)

    - [`camel-case-acronyms`](rust-specific/naming.md#camel-case-acronyms): Use Rust CamelCase with title-cased acronyms (`Nvme`, not `NVME`).

    - [`camel-case-acronyms`](rust-specific/naming.md#camel-case-acronyms)：驼峰缩写：使用 Rust 的 CamelCase，首字母大写的缩写（`Nvme`，而非 `NVME`）。

    - [`closure-fn-suffix`](rust-specific/naming.md#closure-fn-suffix): End a variable holding a closure or fn pointer with `_fn`.

    - [`closure-fn-suffix`](rust-specific/naming.md#closure-fn-suffix)：闭包/函数后缀：持有闭包或函数指针的变量以 `_fn` 结尾。

- [Crates & Modules](rust-specific/crates-and-modules.md)

- [Crates 与模块](rust-specific/crates-and-modules.md)

    - [`workspace-deps`](rust-specific/crates-and-modules.md#workspace-deps): Declare shared dependencies in `[workspace.dependencies]` and reference them with `.workspace = true`.

    - [`workspace-deps`](rust-specific/crates-and-modules.md#workspace-deps)：工作区依赖：在 `[workspace.dependencies]` 中声明共享依赖，并用 `.workspace = true` 引用。

    - [`layered-kernel-crates`](rust-specific/crates-and-modules.md#layered-kernel-crates): Organize kernel crates as an acyclic layered graph, and keep new subsystems, drivers, and utilities outside `aster-core` by default.

    - [`layered-kernel-crates`](rust-specific/crates-and-modules.md#layered-kernel-crates)：分层内核 crates：将内核 crates 组织成无环分层图，默认把新子系统、驱动和工具放在 `aster-core` 之外。

    - [`module-docs`](rust-specific/crates-and-modules.md#module-docs): Open a major module with a `//!` doc: purpose, key types, relation to neighbors.

    - [`module-docs`](rust-specific/crates-and-modules.md#module-docs)：模块文档：主要模块以 `//!` 文档开头：说明目的、关键类型、与相邻模块的关系。

    - [`narrow-visibility`](rust-specific/crates-and-modules.md#narrow-visibility): Start private; widen visibility only when an actual consumer requires it.

    - [`narrow-visibility`](rust-specific/crates-and-modules.md#narrow-visibility)：窄可见性：默认私有；只有实际消费者需要时才扩大可见性。

    - [`encode-intent-in-vis`](rust-specific/crates-and-modules.md#encode-intent-in-vis): A visibility modifier declares an item's maximum intended exposure, regardless of what its ancestors allow.

    - [`encode-intent-in-vis`](rust-specific/crates-and-modules.md#encode-intent-in-vis)：可见性表达意图：可见性修饰符声明项的最大预期暴露范围，与祖先允许的范围无关。

    - [`qualified-fn-imports`](rust-specific/crates-and-modules.md#qualified-fn-imports): Import the parent module and call free functions/statics through it, not by bare name.

    - [`qualified-fn-imports`](rust-specific/crates-and-modules.md#qualified-fn-imports)：限定函数导入：导入父模块，通过它调用自由函数/静态项，而不是直接用裸名。

- [Types & Traits](rust-specific/types-and-traits.md)

- [类型与 Trait](rust-specific/types-and-traits.md)

    - [`rust-type-invariants`](rust-specific/types-and-traits.md#rust-type-invariants): Use the type system (newtypes, enums, generics) to make illegal states unrepresentable.

    - [`rust-type-invariants`](rust-specific/types-and-traits.md#rust-type-invariants)：类型不变量：利用类型系统（newtype、枚举、泛型）让非法状态不可表示。

    - [`enum-over-dyn`](rust-specific/types-and-traits.md#enum-over-dyn): For a closed set of variants, prefer an `enum` over `Box<dyn Trait>`.

    - [`enum-over-dyn`](rust-specific/types-and-traits.md#enum-over-dyn)：枚举优于 dyn：对于封闭的变体集合，优先使用 `enum` 而非 `Box<dyn Trait>`。

    - [`getter-encapsulation`](rust-specific/types-and-traits.md#getter-encapsulation): Prefer a getter over a public field; it preserves naming freedom and room for invariants.

    - [`getter-encapsulation`](rust-specific/types-and-traits.md#getter-encapsulation)：Getter 封装：优先使用 getter 而非公开字段；这保留命名自由和添加不变量的空间。

- [Functions & Methods](rust-specific/functions-and-methods.md)

- [函数与方法](rust-specific/functions-and-methods.md)

    - [`no-bool-args`](rust-specific/functions-and-methods.md#no-bool-args): Avoid boolean parameters that select behavior; split the function or use a typed enum.

    - [`no-bool-args`](rust-specific/functions-and-methods.md#no-bool-args)：杜绝布尔参数：避免用布尔参数选择行为；拆分函数或使用类型化枚举。

    - [`block-expressions`](rust-specific/functions-and-methods.md#block-expressions): Use a block expression to scope temporary state that only produces one value.

    - [`block-expressions`](rust-specific/functions-and-methods.md#block-expressions)：块表达式：用块表达式限定只产生一个值的临时状态。

    - [`minimize-nesting`](rust-specific/functions-and-methods.md#minimize-nesting): Flatten nesting past ~3 levels with early returns, guard clauses, `let…else`, `?`, `continue`.

    - [`minimize-nesting`](rust-specific/functions-and-methods.md#minimize-nesting)：减少嵌套：用提前返回、守卫子句、`let…else`、`?`、`continue` 把嵌套压平到约 3 层以内。

    - [`explain-variables`](rust-specific/functions-and-methods.md#explain-variables): Bind intermediate results of a complex expression to well-named variables.

    - [`explain-variables`](rust-specific/functions-and-methods.md#explain-variables)：解释性变量：把复杂表达式的中间结果绑定到命名良好的变量。

- [Attributes & Macros](rust-specific/attributes-and-macros.md)

- [属性与宏](rust-specific/attributes-and-macros.md)

    - [`expect-dead-code`](rust-specific/attributes-and-macros.md#expect-dead-code): Allow `#[expect(dead_code)]` only for a planned, clear, simple future use.

    - [`expect-dead-code`](rust-specific/attributes-and-macros.md#expect-dead-code)：预期死代码：仅在有计划的、清晰的、简单的未来用途时才允许 `#[expect(dead_code)]`。

    - [`alphabetical-attrs`](rust-specific/attributes-and-macros.md#alphabetical-attrs): Sort outer attributes alphabetically; place `#[derive(...)]` last with sorted traits.

    - [`alphabetical-attrs`](rust-specific/attributes-and-macros.md#alphabetical-attrs)：属性字母序：外层属性按字母顺序排序；把 `#[derive(...)]` 放在最后，trait 也按字母排序。

    - [`narrow-lint-suppression`](rust-specific/attributes-and-macros.md#narrow-lint-suppression): Suppress a lint at the narrowest scope (item/method), not a whole type or module.

    - [`narrow-lint-suppression`](rust-specific/attributes-and-macros.md#narrow-lint-suppression)：窄范围抑制 lint：在最窄作用域（项/方法）抑制 lint，而不是整个类型或模块。

    - [`macros-as-last-resort`](rust-specific/attributes-and-macros.md#macros-as-last-resort): Prefer functions and generics; use a macro only when the type system can't express the need.

    - [`macros-as-last-resort`](rust-specific/attributes-and-macros.md#macros-as-last-resort)：宏作为最后手段：优先使用函数和泛型；只有类型系统无法表达需求时才使用宏。

- [Comments](rust-specific/comments.md)

- [注释](rust-specific/comments.md)

    - [`rfc1574-summary`](rust-specific/comments.md#rfc1574-summary): First doc line is one sentence — a third-person verb for functions, a noun phrase for types/modules.

    - [`rfc1574-summary`](rust-specific/comments.md#rfc1574-summary)：RFC1574 摘要：文档第一行是一句话——函数用第三人称动词，类型/模块用名词短语。

    - [`comment-punctuation`](rust-specific/comments.md#comment-punctuation): End full-sentence comments with terminal punctuation.

    - [`comment-punctuation`](rust-specific/comments.md#comment-punctuation)：注释标点：完整句子注释以终端标点结尾。

    - [`backtick-identifiers`](rust-specific/comments.md#backtick-identifiers): Wrap identifiers in doc comments in backticks; prefer rustdoc links where possible.

    - [`backtick-identifiers`](rust-specific/comments.md#backtick-identifiers)：反引号标识符：文档注释中的标识符用反引号包裹；优先使用 rustdoc 链接。

    - [`no-impl-in-docs`](rust-specific/comments.md#no-impl-in-docs): Doc comments describe what an API does and how to use it, not its internal implementation.

    - [`no-impl-in-docs`](rust-specific/comments.md#no-impl-in-docs)：文档不写实现：文档注释描述 API 做什么以及如何使用，而不是其内部实现。

No **path-specific** guidelines yet.

目前尚无 **路径特定** 的指南。
