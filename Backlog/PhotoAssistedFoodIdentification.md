# P3 — Photo-assisted food identification

## Outcome

Let a person take or choose a food photo, identify plausible foods entirely on device, correct the proposal through the clarification engine, and continue through the existing USDA/review flow. The photo is evidence, never a nutrition source or an automatic log.

The clarification and confirmation engine is a prerequisite. Photo input should not ship as a parallel flow with weaker confirmation semantics.

## Verified iOS 27 API surface

The installed Xcode 27 beta iOS 27 SDK exposes Foundation Models image prompt attachments:

- `Attachment<ImageAttachmentContent>` conforms to `PromptRepresentable`.
- Initializers accept `CGImage`, `CIImage`, `CVPixelBuffer`, or an image file URL.
- Each initializer accepts an optional `CGImagePropertyOrientation`.
- A text label can be attached before including the image in a `Prompt`/prompt-builder request.

This confirms an iOS 27 code path can pass an image to a `LanguageModelSession`; it does **not** establish a food-specific vision guarantee.

API and product gaps that require a spike:

- The public interface inspected here does not state supported pixel dimensions, encoded size, compression, color space, or memory budget.
- It does not expose calibrated food confidence, ingredient provenance, bounding boxes, or a food-segmentation result.
- Image attachment availability does not guarantee equivalent behavior in Simulator, on every Apple Intelligence-eligible device, across languages, or across later beta seeds.
- The model may identify a visible dish but cannot reliably infer hidden ingredients, exact cooking fat, recipe quantities, brand, or mass from appearance alone.
- Camera capture, PhotosPicker integration, orientation normalization, and permission UX remain app responsibilities.

Recheck the compiled SDK and Apple beta release notes before implementation. Keep image support behind a capability/availability adapter so a changed or removed beta API does not break text logging.

## Input and permission UX

- Add **Take Photo** and **Choose Photo** behind the composer’s explicit attachment/manual affordance; never launch a permission sheet on app start.
- Use the system camera interface or a narrowly scoped camera component with just-in-time `NSCameraUsageDescription` permission.
- Prefer SwiftUI `PhotosPicker` for user-selected library access; do not request broad photo-library access when the system picker is sufficient.
- Explain denial with a text-entry fallback and a Settings route only when useful.
- Show the chosen image as a removable local draft attachment and support cancellation at every processing stage.
- Camera and picker controls require VoiceOver labels, permission explanations, large targets, Dynamic Type, and hardware/switch-control reachability.

## On-device image pipeline

1. Load only the selected asset into a scoped temporary representation.
2. Apply EXIF orientation correctly and normalize mirrored camera frames.
3. Downsample before model input, preserving aspect ratio. Determine maximum dimension and memory threshold from device profiling rather than assuming an undocumented API limit.
4. Render to a standard color space and strip location/EXIF metadata from any temporary derivative.
5. Construct the iOS 27 image attachment with explicit orientation and a non-sensitive label.
6. Request a small guided structure of visible food observations, possible components, preparation cues, and ambiguity—not nutrition values.
7. Release decoded buffers promptly and delete temporary files after the draft completes or is cancelled.

No original or derivative image is uploaded to USDA, Cloudflare, analytics, crash attachments, or any other backend. After user confirmation, only the same derived food search terms used by text logging may be sent transiently to USDA.

## Identification and mapping

- Map each plausible visible food into the clarification engine’s evidence/provenance structure, then into `ParsedFoodRequest` only after confirmation.
- Preserve any user caption as separate explicit evidence and let it override an image-only guess.
- Do not output calories, nutrients, serving size, weight, or brand from pixels.
- Treat dish identity, preparation, and quantity as uncertain unless directly supported and confirmed.
- If the model is unavailable, rejects image content, exceeds context, or times out, keep the photo removable and offer text description/manual entry. Text logging must remain fully functional.

## Multiple foods and hidden ingredients

- A photo may propose multiple visible foods, but image attachments do not provide a guaranteed segmentation/bounding-box API. Present a user-editable list rather than implying precise spatial detection.
- Let the user remove, rename, combine, or split proposed foods and enter a quantity for each.
- If boundaries are unclear, ask one targeted question or request a text description; do not recursively crop the image without an explicit, tested design.
- Never silently invent dressing, butter, oil, sauces, cheese, fillings, recipe components, or their quantities. Ask, omit, or choose one authoritative prepared-food record with clear disclosure.
- Route confirmed multi-food results into the Composite Foods model when that feature is available; otherwise create separate reviewed drafts.

## Phased implementation

### Phase 0 — Device spike

- Compile the attachment API against the current beta SDK and test eligible physical devices.
- Measure cold/warm latency, memory, thermal behavior, orientation, HEIC/JPEG/PNG inputs, and structured-output accuracy.
- Establish downsampling limits and cancellation behavior without persisting photos.

### Phase 1 — Picker and one-food proposal

- Ship PhotosPicker before camera if it reduces permission and lifecycle risk.
- Support one image, one proposed food, optional user caption, clarification, and text fallback.

### Phase 2 — Camera and multiple visible foods

- Add just-in-time camera capture and explicit multi-food confirmation/editing.
- Integrate Composite Foods only after its aggregation and persistence rules are stable.

### Phase 3 — Product hardening

- Add performance budgets, memory-pressure recovery, beta-API compatibility checks, accessibility, localization, and privacy/App Store review.

## Tests

- Compile-time adapter tests against the supported iOS 27 API surface
- Fixture tests for every EXIF orientation, mirrored capture, wide/tall images, transparency, HEIC/JPEG/PNG, corrupt assets, and oversized inputs
- Buffer/file cleanup, cancellation, memory-warning, and background/foreground tests
- Model unavailable/not-ready, unsupported content, context limit, timeout, and text fallback tests
- Corpus tests for single foods, mixed plates, sandwiches, salads, restaurant dishes, deceptive packaging, low light, blur, and non-food images
- Assertions that hidden ingredients, quantity, brand, and nutrition are never promoted without evidence/user confirmation
- No-network tests proving image bytes never leave the device; request inspection proving USDA receives derived text only
- Camera denial, picker cancellation, VoiceOver, Dynamic Type, RTL, and Reduce Motion UI tests

## Activation criteria

- Clarification and confirmation engine is shipped and passes its accessibility/privacy gates.
- Current beta attachment API passes a physical-device compatibility spike on the minimum supported hardware.
- A representative labeled corpus establishes useful top-choice/top-three accuracy and measures unsafe hidden-ingredient/quantity guesses; thresholds are set before launch, not after implementation.
- p95 latency, peak memory, cancellation, and thermal behavior meet documented device budgets.
- Every result is reviewable/editable, text/manual fallback is always reachable, and no image bytes appear in network or diagnostic audits.
- User testing demonstrates photo input is faster or meaningfully easier than typing without increasing incorrect confirmed logs.
