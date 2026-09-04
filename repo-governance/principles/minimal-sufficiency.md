# Minimal Sufficiency

Work efficiently, never carelessly. Do the least work that fully satisfies the requested outcome and applicable repository rules. Every line and mechanism creates continuing maintenance, review, testing, security, and removal costs; building is a means, not evidence of progress.

## Understand First

Read the task and the code, specifications, and tests it touches, then trace the real flow end to end before choosing a solution. A bug report names a symptom, not necessarily its cause: find every caller of the behaviour being changed and fix the earliest shared responsible point once. A small diff in the wrong place is unfinished work.

## Reuse Ladder

After understanding the problem, stop at the first rung that fully meets the need:

1. Do not build it when the outcome does not require it (YAGNI).
2. Reuse an existing repository helper, utility, or pattern.
3. Use the language standard library.
4. Use a native platform feature.
5. Use an already-installed dependency.
6. Express it as one clear line when one line remains correct and readable.
7. Only then write the minimum new code that works.

## Constraints

- Do not add abstractions, dependencies, or boilerplate that the requested outcome and applicable rules do not require.
- Prefer deletion over addition, boring over clever, and fewer changed files. The shortest correct diff wins only after the flow is understood.
- When a complex requested mechanism exceeds the actual outcome, establish whether a simpler existing solution covers it before building the mechanism.
- Among equally small standard-library approaches, choose the edge-case-correct one rather than the flimsier algorithm.
- Mark a deliberate simplification that accepts a material ceiling, such as a global lock, quadratic scan, or naive heuristic, with a comment naming the ceiling and upgrade path. Do not annotate ordinary trade-offs.

## Non-Negotiable Work

Minimality never excuses incomplete understanding, trust-boundary input validation, error handling that prevents data loss, security, accessibility, real-hardware calibration, or an explicit request or repository rule. Do not convert a one-time change into generalized machinery or speculative enforcement without demonstrated need.

Non-trivial new or changed logic must leave behind the narrowest runnable regression check that would fail if it broke. Reuse the repository's test infrastructure; do not add a framework or fixtures solely for that check. A trivial one-line implementation needs no dedicated test only when it changes no governed behaviour and no applicable rule requires one. Existing TDD, specification, coverage, and quality-gate requirements still apply.

Keep verification proportional to the change and its risk. Stop when the outcome is achieved and every required check passes. Among compliant solutions, prefer the one with less lasting complexity and maintenance burden.

This principle is subordinate to the repository [vision](../vision/README.md). Every convention, development standard, and workflow must conform to it.
