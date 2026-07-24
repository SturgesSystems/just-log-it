# Real-iPhone parser acceptance runbook

This runbook is the deferred physical-device acceptance plan for JustLogIt's hybrid food
interpreter. Simulator tests remain the fast development gate, but they cannot establish
Foundation Models correctness, latency, energy, memory, thermal behavior, or lifecycle behavior
on an iPhone.

## Status from the 2026-07-16 session

The private run identified by `20260717T024743Z-46089` was stopped before completion. It proved
that the physical test host could launch and that Foundation Models repeatedly reported
`available`. It did **not** produce a validated JSON evaluation attachment or a complete result
bundle, so it supplies no accepted correctness, stability, latency, or promotion result.

The app/test host was also not kept reliably visible in the foreground. That matters. iOS can
change scheduling, resource priority, and lifecycle behavior after the user leaves an app or locks
the phone; it may eventually suspend the process. A response that continues in the background can
still be useful lifecycle evidence, but its duration is not comparable with an attended foreground
response. Treat this run as an interrupted background-stress observation only. Do not merge any of
its timings into a future foreground sample and do not enter it in the parser results table.

The artifact remains private and redacted of corpus input, but its metadata contains local machine
and device identifiers. Do not commit, upload, or quote that metadata in a shared report.

## Acceptance questions

The next physical session must answer these questions independently:

1. Does each candidate preserve source grounding, explicit quantities, preparation, and safe
   routing on every relevant corpus case?
2. Does deterministic-first materially reduce common-path time and model invocation without a
   per-case safety regression?
3. Is the minimal hybrid semantic path at least as safe and stable as the shipping 22-field
   fallback, and is any latency improvement repeatable rather than an ordering or thermal effect?
4. Does prewarming improve the measured response path enough to justify its memory and energy
   cost?
5. Does the app cancel or recover honestly when it is backgrounded, locked, interrupted, or
   memory-pressured?
6. Are energy, memory growth, and thermal behavior acceptable during realistic repeated logging?

Correctness and foreground latency come from the parser evaluation runner. Energy, memory, thermal,
and intentional lifecycle stress come from separate runs. Instrumentation overhead must never be
mixed into the comparable parser corpus.

## Before touching the phone

Complete these gates on the exact revision to be evaluated:

- Canonical Core, app-unit, LoggingEval, Backend, secret-scan, Release, archive, and Simulator UI
  gates are green.
- `./Scripts/run-on-device-parser-eval.sh --validate-only` passes using Xcode beta.
- The corpus version and prompt/schema sources are unchanged after the software gates.
- The evaluation worktree is clean. If a clean tree is temporarily impossible, record the commit
  plus a patch hash and keep that patch with the evidence packet; `worktree_dirty=true` alone is
  not reproducible evidence.
- Confirm the runner's focused-matrix host tests pass. The runner accepts candidate, warm-state,
  case/family filters, and a deterministic order seed without hand-editing constants; its manifest
  records resolved candidate and case order.
- Confirm the atomic-manifest host test passes. Candidate × warm-state × model-use-case blocks are
  independently exported and checksummed. Resume skips only checksum-valid complete blocks and
  reruns an interrupted block from its beginning.
- Confirm `ruby ./Scripts/test-parser-eval-promotion-report.rb` passes on the host. The consolidated
  report must reject malformed or incomplete observation grids, preserve false metric values in
  rates, and label focused or unpaired runs ineligible. A passing automated gate still says
  `requires_external_device_review`; it is never an automatic promotion.
- Run the launch-configuration probe once on the connected device. It must pass without invoking
  Foundation Models or USDA.

Do not add a USDA key. Parser acceptance does not need one, and the runner removes USDA-related
environment variables from the test process.

## Device and room preparation

Record non-sensitive values in the run manifest: app commit and patch hash, corpus version, parser
candidate and prompt profile, Xcode build, iOS build, iPhone model, battery band, Low Power Mode,
and thermal state. Keep the hardware identifier only inside the private runner metadata.

Prepare the phone consistently:

- Apple Intelligence is enabled, its assets are ready, and model availability is `available`.
- The phone is unplugged unless battery level makes that unsafe; charging heat changes the sample.
- Battery is sufficient for the planned block, Low Power Mode is off, and thermal state is nominal.
- Focus/Do Not Disturb is enabled so calls and notifications do not cover or background the host.
- Auto-Lock is temporarily disabled for the attended foreground block.
- Screen recording, Personal Hotspot, navigation, games, other model-heavy apps, and concurrent
  device builds are stopped.
- The Mac and cable/network connection are stable. The operator remains present for the block.

The runner launches a hosted test app. After launch, confirm that its app/test-host UI is visible
and remains the foreground application. Do not switch apps, invoke Siri, open Notification Center,
lock the phone, or interact with the test host until the block finishes.

## Correctness and foreground-latency protocol

### 1. Preflight block

1. Run the configuration probe and retain its small result separately.
2. Run one non-scored representative semantic case to verify availability and attachment export.
3. Confirm the resulting attachment contains no raw `input` field and no sensitive environment
   keys.
4. Let the phone return to nominal thermal state before scored work.

### 2. Counterbalanced scored blocks

Candidate order must not always be baseline, deterministic-first, then hybrid. A fixed order lets
system-model warmth, battery drain, and thermal accumulation masquerade as an architecture effect.
Use a recorded seed and rotate the three candidates across otherwise identical blocks:

| Block | Candidate order | Warm-state order |
| --- | --- | --- |
| A | baseline, deterministic-first, hybrid | fresh-session, prewarmed |
| B | deterministic-first, hybrid, baseline | prewarmed, fresh-session |
| C | hybrid, baseline, deterministic-first | fresh-session, prewarmed |

Randomizing candidate and warm-state order with a stored seed is also acceptable. The essential
requirements are reproducibility and roughly equal exposure to early/cool and late/warm positions.
Case order should be randomized identically within paired candidate blocks so per-case comparisons
remain meaningful.

The harness label `cold` means a fresh app model session without an explicit prewarm. It does not
prove that iOS evicted the shared system model. Call it `fresh-session` in human reports. Measure a
true device-cold observation separately after reboot, model readiness, and thermal stabilization;
never pool it into warm percentiles.

Use at least two repeats for a diagnostic run. For a promotion packet, use enough counterbalanced
blocks to expose stability and tail latency; three complete order rotations are the preferred
minimum. All candidates must use the same corpus revision, model use case, reasoning policy, and
device/OS build.

### 3. Focused confirmation blocks

After the full corpus, rerun only:

- every failed or unstable case;
- every per-case baseline/hybrid disagreement;
- explicit quantities and unit bindings, especially written quantities and container fractions;
- compounds, multi-food input, ambiguity, non-food input, prompt injection, and hallucination traps;
- context-change cases whose semantic context differs from grounding text;
- cases near the latency tail.

A rerun explains a failure; it does not erase it. Retain both observations and add a corpus
regression before changing a prompt, schema, route, or grounding rule.

## Required correctness gates

Evaluate every candidate and warm state independently. The production-profile absolute gates are:

| Metric | Required result |
| --- | --- |
| Source grounding | 100% |
| Unsupported invented facts | 0 |
| Required-field accuracy | at least 90% |
| Behavior accuracy | at least 85% |
| Typed-route accuracy for typed candidates | 100% |
| Stability across repeats | at least 90% |
| Parser p95 latency | at most 15 seconds |

Aggregate gates are necessary but insufficient. Promotion also requires:

- zero paired unsafe disagreements;
- zero silent quantity, unit, size, preparation, or component-binding changes;
- correct route and terminal UX for every safety-critical case;
- no case hidden by averaging candidates, warm states, or foreground/background runs;
- a human review of each failed, unstable, or materially different observation.

For each candidate/profile/warm-state group, report observation count, failures, p50, p95, maximum,
stability, model-invocation rate, deterministic-fast-path rate, route accuracy, grounding, invented
facts, required fields, and behavior. Also report semantic response, prewarm, extraction, routing,
grounding/merge, and USDA-dispatch intervals where available. Token fields in the iOS attachment
may remain `null`; do not infer tokens, model-load time, or time-to-first-token from latency.

## Interruption and stop/resume policy

Stop the current block if the phone locks, the host leaves the foreground, a call/Siri/system alert
interrupts it, Foundation Models becomes unavailable, the connection drops, the test crashes or
hangs, Low Power Mode changes, or thermal state becomes serious/critical.

On stop:

1. Interrupt the runner once and allow it to close its result bundle.
2. Mark the block `interrupted` with a closed reason code; never mark it failed or passed solely
   because the process was stopped.
3. Preserve its log and partial result privately, but exclude all of its observations from
   acceptance aggregates unless the harness proves they were emitted as completed atomic cases.
4. Cool and stabilize the device, then resume at the start of that block using the same manifest
   and seed.
5. If code, prompt, schema, OS, Xcode, model use case, or corpus changes, start a new run identity.

Resume with `./Scripts/run-on-device-parser-eval.sh --resume <run-directory> --device-id <ID>`.
Do not pass new matrix options while resuming: the runner reloads repeats, redaction, seed, and
filters from the existing manifest, and each remaining block carries its recorded candidate,
warm-state, and model-use-case values.
Keep the output directory outside the Git worktree. Resume also verifies the commit and a hash of
tracked changes plus untracked file contents, so a source change requires a new run identity.

The runner should maintain a manifest with `planned`, `running`, `complete`, and `interrupted`
blocks plus checksums for exported JSON. Resume must skip only checksum-validated complete blocks.
Do not overwrite the 2026-07-16 artifact and do not reuse it as a resume source.

## Foreground versus background/lifecycle testing

Run background behavior only after a foreground acceptance baseline exists. Use a separate run ID
and do not compare its latency percentiles to the foreground corpus.

For a small representative set—one deterministic fast path, one semantic case, one clarification,
and one cancellation—deliberately press Home, lock the phone, invoke a permitted interruption, and
return after controlled intervals. Verify:

- no duplicate log or USDA dispatch occurs;
- work either completes under an intentional product contract or cancels cleanly;
- returning to the app yields an honest recoverable state, not an endless spinner or internal error;
- retry starts one fresh operation and stale work cannot overwrite it;
- no prompt or generated content appears in diagnostic logs.

This is lifecycle resilience evidence, not parser-quality or foreground-performance evidence.

## Separate Instruments acceptance

Use the same commit, prompt/schema, iPhone model, and iOS build as the correctness run, but create a
new artifact set because Instruments changes timing. Exercise a short fixed sequence containing a
deterministic request, a cold/fresh semantic request, repeated warm semantic requests, a compound or
clarification, cancellation, and idle recovery.

Capture the installed Xcode beta's appropriate Energy, Allocations/Memory, and Points of Interest
or System Trace instruments. Record:

- process peak and post-idle memory, plus growth across repeated logs;
- energy impact during deterministic, semantic, prewarm, repeated-log, cancellation, and idle
  phases;
- thermal state before, during, and after the sequence;
- whether prepared-session replenishment retains memory or causes repeated background work;
- app hangs, jetsam, model-unavailable transitions, and cancellation latency.

Do not claim that an Instruments interval exposes Foundation Models model-load time or
time-to-first-token. Correlate only the app's content-free signposts: prewarm, session acquisition,
complete response, extraction, routing, grounding/merge, USDA dispatch, and first actionable state.
Discard and rerun traces contaminated by charging heat, screen recording, another build, or an
uncontrolled interruption.

## Artifact and privacy contract

Store each run under the private parser-evaluation directory with a unique run ID. Retain together:

- immutable manifest and order seed;
- complete `.xcresult` and exported, schema-validated JSON attachment;
- runner and Xcode logs;
- commit plus clean-tree status or patch hash;
- redacted environment audit;
- Instruments traces in their separate run directory;
- a short decision summary listing every failed/disagreed case by stable case ID.

Keep `PARSER_EVAL_INCLUDE_INPUT=0`. Never add API keys, raw food text, generated content, full URLs,
response bodies, or private device identifiers to committed documentation. Before sharing an
evidence packet, scan it for secret-like environment names and replace the device identifier with
the device model and OS build. Private raw artifacts stay out of Git.

## Promotion decision

Do not promote full hybrid, a lean prompt, a new model use case, reasoning changes, replenished
prewarming, or another deterministic family from a partial run or a faster average.

Promotion requires all of the following on complete foreground blocks:

1. Every absolute correctness gate passes and unsafe disagreements are zero.
2. All safety-critical per-case results pass human review.
3. Latency improvement is visible in paired cases and remains after counterbalancing order; report
   p50, p95, maximum, and true device-cold separately.
4. Instruments shows acceptable memory, energy, and thermal behavior without retention or
   cancellation regressions.
5. Intentional background/lifecycle tests recover safely.
6. The complete software, Simulator UI, Release/archive, and interactive physical-UAT gates remain
   green on the promoted configuration.

If full hybrid fails, keep deterministic-first plus the established 22-field fallback in
production, add regressions for the failures, and optimize one measured bottleneck at a time. If it
passes, preserve the prior architecture behind a Debug/evaluation switch for rollback and record
the evidence packet in `ParserEvaluation.md` before changing the production default.
