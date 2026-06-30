# Final fix report

## Finding addressed
The review finding was that **Add second device** was always available, even while the popover was already in a sharing state or after an issue. In the existing model, `SharePodsState.addSecondDevice()` only connected the next disconnected device and cleared `hasIssue`, which meant it could leave existing `isSharing` flags intact and preserve a misleading UI state such as “Sharing audio” while the newly added device was only connected.

## Fix applied
- `SharePodsState.addSecondDevice()` now returns immediately unless `mode == .idle`.
- `SharePodsPopover` now disables the `Add second device` mock-control button unless `state.mode == .idle`.
- Added focused model coverage proving that calling `addSecondDevice()` while already sharing leaves the connected-device count and sharing-device count unchanged.

## Files changed
- `SharePods/SharePodsState.swift`
- `SharePods/SharePodsPopover.swift`
- `SharePodsTests/SharePodsStateTests.swift`

## Behavioral result
The mock-control path can no longer move the model into a partially updated state by adding a second device while sharing is active. The add action is now setup-only, and the UI reflects that constraint by disabling the control outside idle mode.

## Verification
Per controller instruction, xcodebuild/test/lint/format/project-wide gates were intentionally not run.
