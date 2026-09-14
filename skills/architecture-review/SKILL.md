---
name: architecture-review
description: Review an existing or proposed structure - boundaries, dependency direction, data model, failure behavior, migration shape - and return a ranked verdict. Use before adopting a design, when a change keeps touching the same seams, or when someone proposes a new layer, service, or abstraction.
---

# Architecture review

Judge structure against constraints, not against taste.

## Procedure

1. **Recover the constraints** before reading the design: correctness, latency,
   cost, data that already exists, team size, deployment and operational
   reality. A review that ignores one hard constraint is decoration.
2. **Describe the current structure honestly**, including what works. Name the
   real boundaries, the direction dependencies point, and where state lives.
3. **Locate the pressure.** Which concrete, observed pain motivates the change?
   If the answer is a hypothetical, that is the finding: the simpler structure
   holds until a named pressure breaks it.
4. **Check the load-bearing properties:**
   - does a dependency point from stable toward volatile, or the reverse
   - can each part fail alone, and is that failure observable
   - is there one owner per piece of state, or several writers
   - what has to change together for a typical change - that coupling is the
     real architecture
   - how the migration runs while the system stays up
5. **Weigh at most three options.** For each: cost, benefit, what it
   forecloses, and the condition that would make it right. Prefer the
   structure that is easiest to delete when evidence is thin.
6. **Recommend one** and say why the others lose.

## Output

A decision with its rationale and consequences, ranked findings with the
condition that triggers each, the first implementation step someone else can
take, and an explicit list of what you did not decide and what evidence would
change the call.
