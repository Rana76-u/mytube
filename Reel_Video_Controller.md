# Task: Implement a Production-Quality Short-Form Video Playback Controller

## 1. Objective

Design and implement a polished, responsive, and production-quality video interaction system inspired by TikTok, Facebook Reels, and YouTube Shorts.

The controller must support intuitive touch gestures, precise seeking, temporary playback-speed control, persistent speed locking, favorites, and contextual on-video feedback.

**Primary goal:** Make video interactions feel immediate, smooth, predictable, and natural on Android touchscreen devices, including during rapid gesture sequences.

Do not simply add independent gesture detectors to the video player. First analyze the existing project architecture, video playback implementation, gesture handling, state management, and UI conventions. Then implement a coordinated gesture-recognition and playback-control system that fits the existing architecture.

Do not rewrite unrelated features or introduce unnecessary dependencies.

---

## 2. Required Gesture and Interaction Behavior

### A. Single tap — Play/Pause

- A single tap on the video toggles between playing and paused states.
- Show a contextual play or pause indicator over the video.
- Use a brief, polished animation, such as a fade and scale transition.
- When playing, the indicator should disappear automatically after a short interval.
- When paused, keep a clear play indicator visible until playback resumes or the UI is otherwise intentionally changed.
- Do not display unnecessary playback controls permanently over the video.
- A tap on an interactive control, such as the favorite button, must not accidentally toggle playback.

**Gesture disambiguation:** Delay single-tap execution long enough to distinguish a possible double tap. If a second tap forms a recognized double tap, cancel the pending single-tap action.

### B. Favorite button — Contextual on-video action

- Display an accessible favorite button over the reel.
- Use a recognizable heart icon with visually distinct active and inactive states.
- Allow users to toggle the current video's favorite status by tapping the button.
- Provide a subtle animation when favoriting or unfavoriting.
- Reflect the actual persisted favorite state rather than relying exclusively on a temporary UI flag.
- Prevent taps on the favorite button from propagating to the underlying video gesture detector.
- Keep the control visually unobtrusive and positioned consistently with the existing reel design.

The favorite button should remain available while the user interacts with the video, subject to the existing application's overlay visibility conventions.

### C. Double tap — Favorite

- Double-tapping the video toggles the current video's favorite state.
- Display an animated heart at the approximate location of the double tap.
- If the video is not favorited, mark it as a favorite.
- If it is already favorited, remove it from favorites.
- Synchronize the animation and visible favorite button with the actual favorite state.
- Avoid accidentally toggling playback after a double tap.
- Prevent a double tap on the favorite button itself from triggering a second, unintended favorite action.

**Important:** A double tap used for seeking must not also trigger favorite behavior.

### D. Double tap on the right — Seek forward

- Divide the video interaction surface into configurable left, center, and right regions.
- A double tap in the right-side seek region advances playback by a configurable interval.
- Use 10 seconds as the default interval, but make the value configurable.
- Show a forward-seek animation, including an appropriate directional icon and the seek duration.
- Optionally display a short timestamp or seek indicator showing the resulting position.
- Support repeated double taps, accumulating the requested seek offsets where appropriate.
- Clamp the target position to the video's duration when the duration is known.
- Handle unknown durations and live or non-seekable sources safely.
- Never allow the seek operation to produce an invalid negative position or a target beyond the playable duration.

### E. Double tap on the left — Seek backward

- A double tap in the left-side seek region moves playback backward by the configured seek interval.
- Show a backward-seek animation and an appropriate directional icon.
- Clamp the target position to zero.
- Support repeated double taps without losing previously requested seek offsets.
- Ensure that a backward seek does not also trigger the favorite gesture.

### F. Horizontal swipe — Precise seeking

Implement a horizontal swipe interaction for fine-grained video seeking.

**Interaction requirements:**

- Detect a horizontal drag only after movement exceeds a configurable touch-slop threshold.
- Distinguish horizontal seeking from vertical scrolling between reels.
- Display a dedicated seek-preview overlay while the gesture is active.
- Show the current position, target position, and a visual progress indicator.
- Provide clear visual feedback that seeking is in progress.
- Commit the target position when the gesture ends.
- Cancel or safely finalize the gesture if the user interrupts it, changes reels, or the player is disposed.
- Prevent a completed seek gesture from triggering a tap, double tap, favorite action, or play/pause toggle.

**Seeking model:**

Use a configurable mapping between horizontal movement and the seek offset.

The mapping should account for the screen width, gesture distance, video duration when known, and an adjustable sensitivity factor. Avoid making short swipes excessively sensitive.

For example, a moderate horizontal swipe could move a few seconds, while a longer swipe could move farther through the video.

The preview must remain responsive without repeatedly issuing expensive seek operations to the underlying decoder. Prefer updating the preview during the gesture and committing the final seek on release, unless the existing player supports smooth and reliable live seeking.

Clamp all seek positions to valid bounds.

**Reel-navigation compatibility:**

The existing vertical reel-swiping behavior must continue to work. Horizontal seeking must not unintentionally advance to another reel or interfere with vertical navigation.

If the existing architecture cannot reliably support simultaneous vertical paging and horizontal seeking, choose a deliberate gesture-arbitration strategy and document the trade-off.

### G. Long press — Temporary playback-speed boost

Implement a press-and-hold interaction that temporarily increases playback speed from 1.0x to 2.0x.

**Activation:**

- Activate after a configurable long-press threshold, using the platform's normal interaction expectations as the starting point.
- Immediately display a speed indicator over the video.
- Begin at 1.0x and increase the speed toward 2.0x in configurable decimal increments.
- Use a default increment of 0.1x.
- Display the current speed clearly, for example, `1.1x`, `1.2x`, and so on, until reaching `2.0x`.
- Use a configurable acceleration interval to determine how quickly the speed increases.
- Clamp the temporary boost to a maximum of 2.0x.
- Apply speed changes through the existing playback engine and handle asynchronous updates safely.
- Avoid rebuilding the entire reel page on every speed increment.

**Visual feedback:**

- Display a compact, high-contrast speed indicator near the center or another appropriate position on the video.
- Animate the indicator when the speed changes.
- Optionally use a subtle progress ring or scale effect to communicate the active hold gesture.
- Keep the indicator legible against both bright and dark video content.
- Avoid excessive animation, flashing, or unnecessary overlays.

**Release behavior:**

- Releasing the long press must immediately end the temporary boost.
- Restore playback speed to 1.0x unless a previously locked speed is active.
- Dismiss the temporary speed overlay with a short animation.
- Do not pause playback or accidentally trigger another gesture on release.

**Important:** Do not implement speed acceleration using a blocking delay, busy loop, or repeated timers that continue after the gesture ends. Use a lifecycle-safe scheduling mechanism and cancel all pending work when the hold ends, the reel changes, or the controller is disposed.

### H. Long press and swipe down — Lock/unlock playback speed

Add a deliberate downward-swipe gesture while the long press is active.

This gesture must have priority over ordinary temporary speed acceleration once the downward movement crosses a configurable threshold.

**First downward swipe while holding:**

- Lock the current playback speed.
- Preserve the exact speed reached at the moment the lock is activated.
- Keep that speed active after the user releases their finger.
- Display an explicit locked-speed indicator, such as a lock icon and `Speed locked · 1.6x`.
- Persist the lock for the current reel session until the user explicitly unlocks it or the application applies a documented lifecycle rule.

**Second downward swipe while holding:**

- If the speed is already locked, interpret the downward swipe as an unlock gesture.
- Clear the speed lock.
- Reset the playback speed to 1.0x.
- Remove the locked-speed indicator.
- Ensure that the unlock gesture does not accidentally trigger another action.

**Critical gesture semantics:**

- A normal long press without a downward swipe temporarily boosts playback speed.
- Releasing a normal long press resets the temporary speed to 1.0x.
- A long press followed by a downward swipe locks the speed.
- Releasing after a successful lock must preserve the locked speed.
- A subsequent long press and downward swipe unlocks the speed and resets it to 1.0x.
- Do not interpret an ordinary downward swipe as a speed-lock gesture unless the long-press activation condition has been satisfied.
- Use movement thresholds and directional intent to avoid accidental locking.
- Clearly distinguish a locked state from an ordinary temporary boost.

If the user begins moving downward before the long-press threshold is reached, follow the application's existing vertical navigation behavior rather than incorrectly locking the speed.

---

## 3. Resolve Gesture Conflicts Explicitly

The gesture system must be coordinated. Do not allow independent recognizers to execute conflicting actions for the same interaction.

Implement an explicit gesture state machine or equivalent centralized gesture coordinator.

At minimum, represent these states:

- Idle
- PendingTap
- PendingDoubleTap
- HorizontalSeeking
- VerticalNavigation
- LongPressBoosting
- SpeedLocked
- LockGestureRecognized
- UnlockGestureRecognized
- Disposed

Adapt the states to the actual implementation rather than creating unnecessary complexity. Some states can be represented as orthogonal state properties if that better fits Flutter's gesture model.

### Gesture priority

Apply the following general priority:

1. Interactive overlay controls must receive their intended input.
2. An active speed-lock or unlock gesture takes precedence over ordinary speed acceleration.
3. A recognized horizontal seek must not trigger tap or favorite behavior.
4. A recognized double tap must suppress the pending single-tap action.
5. A long press must not accidentally trigger single-tap playback.
6. Horizontal seek and vertical reel navigation must be mutually exclusive for a given gesture.
7. Only one primary gesture action may be committed for a single pointer interaction.

Use Flutter's gesture-arena system correctly. Do not rely on several overlapping `GestureDetector` widgets with incompatible callbacks and hope that the correct gesture wins.

Where appropriate, use a custom recognizer, a carefully structured pointer-event coordinator, or Flutter's existing gesture recognizers. Select the simplest robust implementation.

Document the chosen priority rules in the code.

---

## 4. Controller UI and Animation Standards

The controller should feel like a modern short-form video player rather than a conventional desktop video player.

### Required visual elements

- Contextual play/pause indicator.
- Favorite button with active/inactive states.
- Animated heart feedback for double-tap favorites.
- Left/right seek feedback.
- Precise-seek preview with current and target timestamps.
- Temporary playback-speed indicator.
- Persistent locked-speed indicator.
- Optional subtle haptic feedback where supported and appropriate.

### Design principles

- Use the existing application design system, theme, spacing, and icon conventions.
- Support dark and bright video backgrounds using contrast-aware overlays.
- Keep animations smooth and short, with configurable durations.
- Avoid blocking the video while feedback animations are running.
- Keep controls appropriately sized for touchscreen interaction.
- Respect system accessibility settings, including reduced-motion preferences where practical.
- Provide semantic labels for important controls.
- Ensure all overlays work in portrait and landscape orientations.
- Avoid unnecessary UI clutter.

Animations should communicate state changes rather than merely decorate the interface.

---

## 5. Recommended Architecture

Keep gesture recognition, playback state, and presentation concerns separate.

Use the project's existing state-management approach and architectural conventions. Do not introduce a second state-management framework solely for this feature.

Suggested responsibilities:

### ReelGestureCoordinator

Responsible for:

- Recognizing and arbitrating gestures.
- Tracking pointer position and movement.
- Distinguishing taps, double taps, long presses, and directional swipes.
- Preventing conflicting gesture actions.
- Cancelling incomplete interactions when necessary.

### PlaybackControllerService

Responsible for:

- Play/pause.
- Seeking and position clamping.
- Playback-speed changes.
- Duration and seekability checks.
- Safe coordination with the underlying video player.
- Handling errors and asynchronous playback operations.

Reuse the existing playback service if one already exists rather than creating a duplicate.

### PlaybackInteractionState

Responsible for exposing UI-relevant state, such as:

- Current playback status.
- Current position and duration.
- Temporary playback speed.
- Locked-speed state.
- Favorite state.
- Active seek preview.
- Active gesture feedback.
- Relevant error or unsupported-operation states.

Prefer immutable state or similarly predictable updates consistent with the existing architecture.

### ReelControllerOverlay

Responsible for rendering:

- Play/pause feedback.
- Favorite control and heart animation.
- Seek feedback.
- Seek-preview overlay.
- Temporary speed indicator.
- Locked-speed indicator.

Keep high-frequency gesture updates localized to the necessary overlay components.

### FavoriteRepository

Use the existing favorite repository or persistence layer. Do not invent a second source of truth for favorite status.

Ensure updates are associated with the correct video ID, not just the currently visible list index.

These are suggested responsibilities, not mandatory class names. Adapt them to the existing project structure.

---

## 6. Playback Engine and Lifecycle Requirements

Before implementation, identify the current video player package and confirm its capabilities.

- Reuse the existing video controller and avoid creating a separate decoder for the same video.
- Ensure speed changes work with the current local and remote video sources.
- Handle unsupported seeking or speed changes gracefully.
- Prevent overlapping asynchronous operations from leaving the playback state inconsistent.
- Avoid updating a disposed controller or widget.
- Cancel active gestures and scheduled work when the reel changes.
- Reset temporary speed to 1.0x when appropriate.
- Do not reset an active speed lock accidentally during a widget rebuild.
- Define and document what happens to locked speed when moving to another reel.
- Ensure the actual playback speed and displayed speed cannot drift apart.
- Handle buffering, errors, completion, and controller initialization.
- Avoid unnecessary player reinitialization when toggling overlays or changing playback speed.

Do not assume every video source supports identical seeking behavior.

---

## 7. Performance and Reliability

Target smooth interactions on ordinary Android devices, not only high-end hardware.

- Avoid expensive synchronous work during pointer events.
- Avoid rebuilding the complete reel feed for every gesture update.
- Avoid excessive position polling.
- Use localized state updates for transient visual feedback.
- Avoid repeated decoder seeks during drag previews unless supported and tested.
- Cancel obsolete asynchronous operations when the active video changes.
- Prevent feedback animations from accumulating indefinitely.
- Keep the implementation compatible with the application's existing caching, playback, and vertical paging behavior.

Do not introduce background services, complex event buses, or extra packages unless there is a demonstrated need.

---

## 8. Acceptance Criteria and Test Plan

Write unit and widget tests for the gesture coordinator and playback-state transitions. Add integration tests where the existing project supports them.

At minimum, verify these scenarios:

1. A single tap toggles play/pause exactly once.
2. A double tap does not trigger the pending single-tap action.
3. A double tap in the center toggles favorite exactly once.
4. A double tap on the left seeks backward without changing favorite state.
5. A double tap on the right seeks forward without changing favorite state.
6. Repeated double taps accumulate seek offsets correctly.
7. Seeking backward never moves before zero.
8. Seeking forward never exceeds a known duration.
9. A horizontal swipe previews and commits a seek without toggling playback.
10. A vertical swipe navigates reels without initiating a horizontal seek.
11. A long press increases speed in decimal increments and stops at 2.0x.
12. Releasing a normal long press restores 1.0x.
13. A downward swipe during an active long press locks the current speed.
14. Releasing after locking preserves the locked speed.
15. A second valid downward-swipe gesture unlocks the speed and resets it to 1.0x.
16. An ordinary vertical swipe cannot accidentally lock playback speed.
17. Rapid gesture sequences do not execute conflicting actions.
18. Changing reels cancels stale gesture operations and feedback.
19. Disposing the player does not produce asynchronous state-update errors.
20. Favorite state remains correct after the relevant persistence operation completes.
21. Playback errors and unsupported operations do not crash the reel screen.
22. Interactive overlay controls do not accidentally trigger underlying gestures.

Test boundary cases, including short videos, videos at their final seconds, repeated seeking, slow initialization, buffering, and rapid reel changes.

Use deterministic gesture timing and fake playback services where practical.

---

## 9. Implementation Workflow

Follow this workflow rather than attempting an uncontrolled rewrite.

### Phase 1 — Inspect

- Inspect the Flutter project structure.
- Identify the existing video player package, controller, reel feed, state-management system, favorite persistence, and vertical navigation implementation.
- Identify any existing gesture-handling logic that must be preserved.
- Report the relevant files and the proposed minimal changes.

### Phase 2 — Design

- Define the gesture state machine and priority rules.
- Specify how single taps, double taps, long presses, horizontal seeks, and downward lock/unlock gestures are distinguished.
- Identify the required state, callbacks, and lifecycle behavior.
- Explain any Flutter gesture-arena constraints that affect the design.

### Phase 3 — Implement the core behavior

Implement playback actions and gesture coordination first.

Ensure that play/pause, favorites, double-tap seeking, precise seeking, temporary speed boosts, and speed locking work correctly before adding decorative animations.

### Phase 4 — Implement UI feedback

Add the overlay controls and animations using the existing theme and component conventions.

Keep transient animation state separate from persistent playback state.

### Phase 5 — Test and refine

- Run formatting and static analysis.
- Run relevant unit and widget tests.
- Run the existing project test suite where feasible.
- Resolve regressions in reel navigation and playback.
- Verify lifecycle cleanup and asynchronous error handling.
- Summarize test results and any limitations that require a physical Android device.

### Phase 6 — Report completion

Provide:

- Files created and modified.
- Architectural decisions.
- Gesture priority rules.
- Tests executed and their actual results.
- Known limitations.
- Any recommended follow-up tasks.

Do not claim tests passed unless they were actually executed successfully.

---

## 10. Constraints

- Follow the existing Flutter architecture.
- Prefer a minimal, maintainable implementation over unnecessary abstractions.
- Do not rewrite unrelated screens or playback features.
- Do not add dependencies without justification.
- Do not change the existing reel feed's visual design beyond what is necessary for the controller.
- Preserve compatibility with existing video sources and favorite persistence.
- Do not silently substitute a different gesture behavior when the requested behavior conflicts with the platform's gesture recognition.
- Document unavoidable trade-offs clearly.

**Definition of done:** The result is a cohesive reel playback interaction system in which every gesture has predictable behavior, conflicting actions are prevented, speed locking works exactly as specified, transient feedback is polished, and playback remains stable during rapid interaction and reel changes.

Begin with Phase 1. Do not implement the entire feature until you have inspected the existing code and established a compatible implementation plan.