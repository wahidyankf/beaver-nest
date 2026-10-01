# Code Standards

Language-neutral rules for authored code that every stack standard here maps to its own tools.

## Directory Map

- [Hexagonal architecture](hexagonal-architecture.md) places application code in bounded contexts with a pure domain, ports, and adapters, and points every dependency inward.
- [Hexagonal architecture modules](hexagonal-architecture/README.md) hold domain-driven design, the layers and dependency rule, application shapes, and test doubles.
- [Shell scripts](shell-scripts.md) require one declared interpreter, strict mode, a committed executable bit, comments, and real JSON parsing.
- [Type and boundary safety](type-and-boundary-safety.md) requires the strongest practical checker and validation where external data arrives.
