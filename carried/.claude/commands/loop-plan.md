# /loop-plan — work a plan to the criteria it claims

**Argument:** the path to a plan document — `/loop-plan docs/plans/2026-01-05-widget.md`.
With no path, or a path that does not exist, say so and stop.

Built to run under a loop — `/loop /loop-plan <path>` — so it re-enters on each tick. It works
standalone; the exits below are the same either way.

## First tick

**Read the plan.** Four parts of it govern this run:

- **`## Criteria coverage`** — the spec criteria this plan claims, and the task discharging each.
  **These, and only these, are the target.** Every criterion on the `Not claimed` line is out of
  scope; working one is scope creep, not diligence. If the plan has no such section, say so and
  ask for the scope rather than inferring it — that inference is the failure the section exists to
  prevent.
- **`Human dependencies`** in the header — what the plan needs from a person, and the task each
  one blocks. Absent means the plan claims to need nothing, which is a claim you may find false.
- **`PR boundaries`** — the pull requests to produce, one child issue each.
- The tasks, in their order.

**Find your position from the tracker, not from the plan.** Read the epic's children checklist and
the open pull requests. A plan's checkboxes are not progress.

**Then state, in one short paragraph:** the criteria in scope, the criteria disowned, the human
dependencies if any, and which pull request you are starting.

## Every tick

Work the next task in the plan's order. Close each child from its pull request body so the link is
automatic, and tick the epic's checklist as children close.

**Never edit the plan.** It is the intent a human approved at the review gate; a plan edited during
implementation is no longer that plan. If it is wrong, stop and say why. The one exception is a
step the plan itself contains — writing assigned issue numbers into its own header, say — and only
where the plan names that edit as a step.

## Merging

**Do not merge unless the person who started this run has said, in this run, that you may.**
Nothing in this file says it, and nothing in it can: a file carried byte-identically into every
repository cannot know whose repository it landed in. Absent that word, take the pull request to
*open, green and reviewed* and stop there, saying so plainly.

Where they have said it, merge only when all of these have been **observed to hold in this run**:

- the repository declares at least one required status check on that branch, **and** every one of
  them has reported success — an empty set of required checks fails this condition rather than
  satisfying it vacuously;
- a code review of the pending diff has been run and its findings resolved;
- a security review of the pending diff has been run and its findings resolved;
- any automated reviewer comments on the pull request have been addressed.

The operator's word is a precondition like the other four, not an override. It makes merging
*possible*, never mandatory, and it excuses none of them.

## Waiting

When the next step waits on something finishing — a status check, a build, a review agent — arm a
monitor for that event instead of sleeping on a timer. A timer that outlasts the event wastes the
whole difference: twenty-five-minute heartbeats spent waiting on checks that finish in three.

## Stopping

Stop on the first of these, and say which:

1. **Done** — every criterion the plan claims passes. Before stopping, report each one on its own
   line with the command that proves it and that command's output. A criterion asserted without
   evidence is not met.
2. **Blocked** — progress needs a credential, account, approval or by-hand operation from a
   person. Stop immediately, name what is needed and which criterion it blocks, and do not work
   around it. Creating the account, or widening your own access, to satisfy a criterion is never
   the answer: needing a person *is* the finding.
3. **Ceiling** — six ticks. Report which criteria pass, which do not, and where the next tick
   would have started.

An epic closing is a consequence of the criteria passing, never the definition of it. "Loop until
the epic can be closed" makes the success condition an act you can perform, which certifies
nothing.
