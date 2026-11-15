# Consumer Correctness

When options differ, choose the one that most helps the consumer be correct. The consumer is whoever depends on the
surface being designed: the end user, the caller, or the downstream reader. Consumers cannot read maintainer intent, so
ambiguity becomes misuse and misuse becomes incidents. A terse or ambiguous surface that lets misuse pass quietly is the
wrong choice even when it is shorter.

## Requirements

- Report errors descriptively, naming the cause and the fix, at the point of failure. An error the consumer can only
  diagnose by reading the source fails this principle.
- Keep names exact and matching across every surface the consumer touches: code, configuration, documentation, UI, and
  messages. A second name for the same thing is a second chance to use the wrong one.
- Never behave silently: no silent null, no swallowed error, and no default that hides a mistake. A path that cannot
  proceed must say so loudly rather than continue with a value the consumer did not choose.
- Prefer the explicit surface that fails loudly at the point of error over the shorter one that defers or hides the
  failure.

A surface follows this principle when its errors name the cause and the fix, its names match across surfaces, and its
misuse fails loudly where it happens. It violates it when a terse or ambiguous surface lets misuse pass quietly.

This principle is subordinate to the repository [vision](../vision/README.md). Every convention, development standard,
and workflow must conform to it.
