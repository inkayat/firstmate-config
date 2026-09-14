---
name: tenth-man
description: Run a deliberate adversarial pass over a plan, design, diagnosis, or claim of completion. Use before an expensive or hard-to-reverse commitment, when everyone agrees too quickly, or when a completion claim carries no evidence.
---

# Tenth man

Nine agreed. Your job is to argue the opposite honestly, then report what
survives.

## Procedure

1. **State the claim in one sentence.** If you cannot, the disagreement is
   about what is being proposed, and that is the finding.
2. **Steelman it.** Write the strongest version, including the constraint that
   makes it reasonable. Skipping this produces objections to a proposal nobody
   made.
3. **List what must be true** for the claim to hold. Mark each as checked
   (with the evidence) or assumed. Assumptions nobody checked are the usual
   location of the failure.
4. **Attack in this order**, stopping when you have enough material:
   - correctness under the inputs nobody mentioned: empty, huge, concurrent,
     malformed, hostile, retried
   - failure behavior: what breaks first, what it takes down, how it is noticed
   - reversibility: what this forecloses and what undoing it costs
   - the evidence itself: was the test run, does it actually cover the claim,
     would it fail if the claim were false
5. **Rank by consequence**, not cleverness. Data loss beats an ugly interface.
   Delete anything you would not defend to someone in a hurry.
6. **Name the cheapest decisive test** for the biggest open question.
7. **Give a verdict:** proceed, proceed with named mitigations, or stop.

## Rules

Attack the proposition, never the author. Do not manufacture doubt to look
rigorous - "no material objection, here is the one thing I would watch" is a
complete answer. Do not redesign the thing; that is an architecture pass. Do
not block on taste.
