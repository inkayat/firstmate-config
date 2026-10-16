# Adaptive workflows

This catalogue owns five alternative recipes for FirstMate to select, not five
stages every task must traverse. It is instruction-level policy, not an
executable selector, state machine, sandbox or new task database. FirstMate
keeps macro orchestration through its existing backlog, dependency, dispatch,
inbox and lifecycle owners. Workers receive a stage; they do not launch the
next macro stage.

## Selection and common contract

Resolve project, authority, outcome and delivery path under
[primary policy](primary-policy.md) first. Consult existing evidence/handoffs;
do not repeat completed research. Choose the smallest recipe that addresses
the **current blocking condition**:

- A requested review, audit, deliberate challenge or validation of an existing
  artifact: [scoped-assessment](#scoped-assessment).
- Meaningful causal uncertainty or an explicit investigation:
  [evidence-first](#evidence-first).
- Materially unsettled structure or consumer contract:
  [design-then-deliver](#design-then-deliver).
- Settled interfaces with separately owned, verifiable deliverables that
  benefit from splitting: [coordinated-delivery](#coordinated-delivery).
- Otherwise, including one coherent mixed deliverable:
  [focused-delivery](#focused-delivery), the generic fallback.

An unexplained cross-layer failure may need evidence before coordination;
a handed diagnosis may already permit focused implementation. A known fix
stays with its implementer. A knowledge-only request ends with knowledge.
File count, a specialist title or risk alone does not justify extra stages.
Use source-reachable technical decisions, not a user workflow menu.

In `## Firstmate spec`, name the workflow ID and one-line fit, stage,
input artifact, scope/exclusions, role, exact context/skill paths, acceptance,
dependencies and delivery/stop boundary. Select category/rule independently
from the complete routing owner before role/model/effort. `architecture` and
`tenth-man` retain their fixed categories and family constraints. Choose a
role compatible with the entire authorized task; explain mixed/generalist
fallback. Roles/defaults are [separate contracts](../roles/), not a roster
of actors that every workflow must instantiate.

Project-native instructions and project-local skills still win. Keep the
two-method/one-reference budget, including defaults and mandatory companions;
a workflow is not a skill bundle or authority for a transitive method cascade.
Keep SELECTED, READ, APPLIED and VERIFIED distinct under primary policy.

When authorized work assesses a claim, begin with the original question and
constraints, then inspect the artifact/evidence before reconciling the author's
attributed account. State the decisive observation or uncertainty in existing
reasoning/reporting and retain material initial disagreement. If prior
conclusions were seen, acknowledge that when relevant; do not hide rationale
or safety inputs to simulate blindness or claim independent discovery. This
orders existing reasoning, not permission for another assessor or stage.

When findings exist, the technical owner consolidates evidence-backed
dispositions in the existing report or selected path's record: fixed, refuted,
unresolved, or expressly waived by the authorized owner, linked to the original
finding, corrected artifact/delta, proof and remaining limit. Authorized closure
uses original findings, the corrected delta, relevant base context and current
inputs/proof; focus on substance and plausible regressions, not a fresh audit
for an unchanged objection without new evidence or requirements. Consider
material new defects, evidence and user requirements; send precise unresolved
issues to their existing owner. The selected path's required rounds and
existing severity/waiver authority win: assertion does not close a BLOCKER,
and implementers cannot self-waive IMPORTANT findings. No findings means no
closure record to invent; add no assessor, parallel ledger or fixed round cap.

All recipes retain project checks and proportionate real CLI/API/client
proof. They add no independent reviewer, manual clean gate, no-mistakes run,
helper permission or model spend. The selected official delivery path alone
owns rigor and publication. No recipe grants commit/push/merge/deploy,
production migration, private-state access or destructive/security authority.
Written restrictions and fixture success do not prove native adoption or
runtime enforcement.

## focused-delivery

**Intent/selection.** One settled outcome with bounded uncertainty and one
coherent owner. Covers docs, tests, config/tooling, fixed-contract backend/UI,
small refactors and mixed work that is cheaper and clearer to keep together.

**Required inputs.** Desired behavior/artifact, current contract and project
versions/instructions, owned paths and exclusions, runnable acceptance,
prerequisite artifacts, delivery authority and stop rule.

**Authorized stages and roles.** One fitting worker handles bounded discovery,
authorized changes and verification. Use django-pro for fixed-contract
Django backend-only work, frontend-master for UI-only work, refactorist for
behavior preservation, technical-writer for settled docs-only work, or
senior-fullstack for mixed/non-domain delivery. Facts-only work can use scout
and end there; its no-execution/no-judgment restriction remains intact.

**Dependencies/handoffs.** Wait only for real prerequisite artifacts/resources.
Move material contract ambiguity to design-then-deliver; independent settled
work need not wait. Same-file overlap is not by itself a semantic dependency.
Do not split merely to exhibit specialists.

**Verification/exit.** Map acceptance to actual commands/scenarios and observed
results, including meaningful behavior tests where required and a changed-path
smoke. Refactors retain before/after proof. Check docs/examples without
executing ungranted install/destructive operations. Report unknowns and stop
at the selected delivery boundary, including uncommitted inspection when
that is the explicit task limit.

**Escalation/limits.** Escalate actual product/scope/authority conflict or a
required verification resource that cannot be reached safely. A large diff
alone creates no review task.

## evidence-first

**Intent/selection.** An unexplained failure, conflicting observations,
intermittent/concurrent behavior, or explicitly requested reproduction and
diagnosis. Use when causal uncertainty can change the fix, not before every bug.

**Required inputs.** Reported failure as ground truth, starting state,
source/ref/version, available logs/reproducer and retained diagnosis, precise
local/test execution permission and excluded live/private resources.

**Authorized stages and roles.** Source inventory may use scout only when a
separate facts deliverable is useful. Runnable diagnosis uses debugger.
An authorized in-task fix stays with its fitting implementer/generalist, who
investigates then fixes. Targeted external research is a separate deliverable
only if necessary to settle semantics. Hard causal work routes DEEP by the
existing criteria, not automatically because debugger was chosen.

**Dependencies/handoffs.** A separate debugger hands FirstMate observed versus
inferred cause, reproducer/result, rejected hypothesis, affected consumers,
scope/exclusions, confidence and a falsification/regression plan. FirstMate
carries that artifact into an already-authorized implementation stage only
when a separate stage is justified. Diagnosis-only scope never promotes itself
to source edits. Structural uncertainty can move the affected part to
design-then-deliver without restarting settled work.

**Verification/exit.** Explain the failure with safe discriminating evidence;
static-only or unreproduced conclusions remain labeled. Diagnosis does not
claim a fix. An authorized fix re-exercises the failing path and relevant
preserved behavior. Stop when further evidence needs ungranted access.

**Escalation/limits.** Report incompatible evidence safe probes cannot resolve,
an unowned risk/product decision or a required authority boundary. Repeated
failed fixes require reevaluation, not endless retries or extra models.

## design-then-deliver

**Intent/selection.** A material unresolved module/domain/API boundary,
migration shape or incompatible consumer contract changes what should be
built. A small implementation question stays in focused-delivery.

**Required inputs.** Outcome/constraints, current source and consumers,
permissions/data invariants, actual versions, exclusions, rollout/reversibility
limits and what implementation is already authorized.

**Authorized stages and roles.** Architecture, in its fixed category, offers
at most three options and one recommendation with a contract/dependency/
acceptance handoff. API design can be its budgeted second method, not a new
contract actor. A settled decision needing explanation can instead use
technical-writer. A deliberate challenge needs its own authorized proposition
and tenth-man's existing category/family bindings; it is never routine.

**Dependencies/handoffs.** Settle interfaces before dependent work. Include
request/response/error/permission behavior, scope/non-goals, versions,
affected consumers, true dependency order, compatibility consequences and
proof plan; include migration population/race/reverse assumptions where
relevant. FirstMate sends authorized implementation to focused or coordinated
delivery. Already-authorized design-then-implementation needs no routine new
approval round. Product decisions that sources cannot settle still escalate.

**Delivery sequence and ownership.** When design and implementation are
authorized, the handoff sequence is:

1. Design settles the decision/contract and acceptance/proof plan.
2. Authorized implementation produces the change against that handoff.
3. The implementer runs actual tests and verification before handing off:
   relevant domain checks for the owned behavior, and cross-component or
   real-flow verification where the change crosses those boundaries.
   Follow project-required checks; do not prescribe every domain suite for
   every task or treat isolated unit results as integrated-flow proof.
4. Independent review comes only from the selected delivery path, not from
   this recipe. If that path supplies none, report that no independent review
   was supplied; never imply one occurred or add a reviewer/manual gate.
5. Findings go through that same owner's authorized fix process, followed by
   repeated relevant verification and any re-review that path requires.
   A requested re-review receives original findings and the corrected delta.

FirstMate orchestrates the handoffs; workers do not self-dispatch stages.
This is not a second pipeline: when no-mistakes is selected, it owns its
review/fix/verification flow, with no duplicate reviewer or outside clean
gate. The sequence neither selects a new delivery mode nor grants additional
actions. Honor the task's explicit stop before any ungranted publication,
including an uncommitted user-inspection boundary.

**Verification/exit.** Tie the recommendation to constraints/consumers and name
unknowns. Implementation returns the smallest incompatibility instead of
inventing missing behavior or silently changing the contract. Proceed under
existing authority when no user decision is needed. A design-only request
ends with its report, not implementation.

**Escalation/limits.** Genuine product/risk/rights/destructive choices,
contradictory project rules or a required official-runtime-owner change go to
FirstMate. Structural advice grants no schema deployment or publication right.

## coordinated-delivery

**Intent/selection.** Settled interfaces span surfaces with independently
implementable, verifiable deliverables whose handoff benefit exceeds splitting
cost. One mixed owner remains valid; file count is not the trigger.

**Required inputs.** Settled contract/version, owned paths, one integration
owner, cross-surface acceptance, true dependency graph, synthetic test
data/environment and each task's delivery limits.

**Authorized stages and roles.** FirstMate names one integration owner,
normally senior-fullstack for a cross-surface result. Separable backend/UI
work can use django-pro/frontend-master. Independent settled docs can use
technical-writer if a separate deliverable is worthwhile. No new coordinator
role; every worker reports to FirstMate within its assigned project/task.

**Dependencies/handoffs.** Existing owners dispatch independent isolated tasks
and serialize true semantic/shared-state prerequisites, not file overlap by
reflex. A client can build against a fixed contract while its provider is
pending, but cannot call the real flow verified. FirstMate carries compatible
source/ref/artifact and verification state through existing reconciliation;
workers never patch sibling or primary copies.

**Verification/exit.** Owned-slice checks plus a real integrated scenario
against the actual changed components. Extension proof names popup/content/
background execution and message paths. Observe API permissions and persistence
where relevant; screenshots/mocks do not prove them. The integration owner
reports combined acceptance and remaining limits under the selected path.

**Escalation/limits.** Return contract conflicts, incompatible migrations/shared
external state or missing integration authority. Mocks support development,
not the integrated-flow exit. No independent reviewer is added by this recipe.

## scoped-assessment

**Intent/selection.** An explicitly authorized knowledge deliverable judging a
named artifact, auditing named security scope, challenging a proposition or
validating already-built behavior. Never an automatic post-implementation gate.

**Required inputs.** Exact question; immutable diff/patch with base/head for
review, assets and access for security, proposition/assumptions for challenge,
or version/starting state/scenario for validation. Specify read-only-source
and runtime-action permissions separately.

**Authorized stages and roles.** Code-reviewer judges a handed diff;
security-engineer provides scoped vulnerability evidence; tenth-man challenges
in its fixed category; architecture recommends structure in its fixed category.
Runnable validation can use senior-fullstack/a domain worker with a bounded
read-only-source brief, not a permanent verifier role. Facts-only inventory
uses scout. No assessment grants fixes or publication.

**Dependencies/handoffs.** An explicitly separate review uses a different
read-only worker from the author through existing control. Re-review receives
original findings and corrected delta. FirstMate receives findings; remediation
is a separately authorized change. Never add an actor atop no-mistakes review.

**Verification/exit.** Code findings name location, concrete failure scenario
and BLOCKER/IMPORTANT/OPTIONAL counts. Security retains severity/confidence,
verified/suspected and negative coverage. Validation reports actual actions,
state and limits. No material findings is valid; a verdict grants no merge
or commit authority.

**Escalation/limits.** Escalate material security findings under the existing
role contract, missing immutable input, ungranted required action or a genuine
decision. Do not widen one concern into a general audit.
