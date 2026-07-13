# P2 — Conversation-first navigation

## Outcome

Make logging the app's persistent home: a calm, chat-inspired conversation where a person can describe food, resolve ambiguity, review nutrition, and confirm the log without moving through a tab hierarchy. Move secondary destinations into an adaptive sidebar that keeps repeat foods close without competing with the composer.

This borrows the spatial model and interaction clarity of modern chat apps, not their personality or message-bubble ornament. The product should remain a precise food logger whose system responses are actionable nutrition states.

## Information architecture

### Main content

- Logging conversation is the default and restores the current in-progress log when the app returns.
- A single bottom-anchored composer accepts natural language and exposes native keyboard dismissal, submit, cancellation, and accessibility actions.
- The transcript contains only useful states: the person's request, parsing/search progress, match choices, quantity clarification, nutrition review, confirmation, and recoverable errors.
- A new-log action clears the transient conversation only after protecting any unsaved review.
- Saved entries remain historical records and are reachable from a dedicated history destination; they are not mixed into the reusable-food list.

### Sidebar

Order the sidebar for frequency of use:

1. New log
2. Log history
3. Recognized foods search field
4. Searchable, scrollable recognized-food list
5. Settings pinned to the bottom, independent of list length

Each food row should prioritize a clear display name, optional brand, and the most useful serving cue. Selecting one begins a new logging turn prefilled with that food; it must not immediately create an entry. Empty, loading, and no-results states should explain the next useful action without decorative filler.

## Data boundaries

- **Entry:** an immutable nutrition snapshot representing something logged at a particular date and quantity. Entry edits or deletion affect history and HealthKit reconciliation.
- **Recognized food:** a reusable identity derived from a confirmed USDA selection or manual food definition. It may reference an FDC ID, retain a user-facing name and serving hints, and track local recency/frequency for ordering.
- **Conversation state:** transient input, candidate results, clarification, and review state. It may produce an entry and update a recognized food only after confirmation.

Do not derive the sidebar by deduplicating entry names at render time. Introduce an explicit local recognized-food model or repository so renamed foods, USDA identity, manual foods, deletion semantics, and ranking remain deterministic. Deleting an entry must not silently delete its recognized food; forgetting a recognized food must not erase history.

## Adaptive behavior

### iPhone portrait and compact width

- Present navigation as a leading-edge drawer or system sheet opened from a clearly labelled toolbar control.
- Keep the logging conversation full width; opening the drawer moves focus into it and dismisses the composer keyboard natively.
- Dismiss with selection, swipe, tap outside, Escape when available, or the explicit close action. Preserve the conversation and scroll position.
- Keep Settings visually anchored at the bottom while the recognized-food list alone scrolls.
- Avoid a permanently compressed split view or custom gesture that conflicts with system back navigation.

### iPad and iPhone landscape when space permits

- Use `NavigationSplitView` with a persistent, resizable sidebar and conversation detail.
- Support sidebar collapse/expand through the system toolbar and keyboard shortcut behavior.
- Preserve selection and column visibility across rotation and scene restoration without treating sidebar visibility as app data.

## Interaction and visual states

- First launch: brief, concrete prompt examples above the composer; no fake conversation history.
- Parsing/searching: one stable progress row with cancellation, avoiding stacked transient messages.
- Candidate selection: concise rows with USDA source context and enough serving information to choose confidently.
- Review: nutrition summary and quantity controls are embedded as one accessible card with an unambiguous Log action.
- Success: a restrained confirmation that offers another log; the saved result appears in history and updates the recognized-food list.
- Failure/offline/model unavailable: preserve the person's text and offer retry or manual entry in place.
- Sidebar loading/empty/search-empty: stable layouts with readable explanations and no disabled mystery controls.

## Accessibility and input quality

- Use system navigation, focus, scroll, sheet, and text-input behavior wherever possible.
- Provide VoiceOver names, values, hints, headings, and ordered focus for the sidebar control, food rows, transcript states, composer, and nutrition actions.
- Announce meaningful asynchronous state changes without reading the entire transcript again.
- Support Dynamic Type without truncating food identity or hiding primary actions; allow rows and cards to grow vertically.
- Maintain 44-point targets, sufficient contrast, Reduce Motion, Voice Control, Switch Control, hardware keyboard traversal, and RTL layout.
- Support native interactive keyboard dismissal while scrolling the conversation and an explicit keyboard-dismiss path where system behavior is not discoverable.
- Do not encode speaker, status, selection, or nutrition warnings by color alone.

## Staged implementation

### Stage 1 — Shell and navigation

- Replace the tab shell with adaptive `NavigationSplitView`/compact presentation while retaining current Log, Entries, and Settings screens.
- Make Log the default detail and verify scene restoration, rotation, deep links, keyboard dismissal, and unsaved-work protection.

### Stage 2 — Recognized foods

- Define the explicit recognized-food model, migration, repository, ordering, search, forget behavior, and tests.
- Populate it only from confirmed USDA or manual logs; selecting a row starts a draft rather than saving.

### Stage 3 — Conversation flow

- Refactor parsing, candidates, clarification, review, errors, and confirmation into a single state-driven transcript.
- Remove superseded tab-era chrome only after every existing recovery and manual-entry path is represented.

### Stage 4 — Product-quality validation

- Test compact and regular widths, rotation, large content sizes, VoiceOver, hardware keyboard, Reduce Motion, offline/error states, large food libraries, and state restoration.
- Measure time to repeat-log, abandoned drafts, incorrect repeat-food selection, and navigation discoverability before promoting the redesign into MVP.

## Acceptance criteria

- App launch and new-log actions land in the conversational logging view.
- Navigation adapts cleanly between compact drawer/sheet and expanded sidebar without losing a draft.
- Settings stays pinned at the bottom; only the recognized-food region scrolls.
- Recognized foods are locally searchable and selecting one starts a reviewable draft.
- History entries and recognized foods have independent, documented deletion behavior.
- All current logging, manual-entry, USDA, HealthKit, error-recovery, and entry-history capabilities remain reachable.
- Keyboard, focus, Dynamic Type, VoiceOver, and restoration behavior pass the launch accessibility matrix.
