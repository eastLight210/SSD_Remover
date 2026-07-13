# Design QA

## Result

Passed

## Reference

- Figma: https://www.figma.com/design/JPI8IridYuEbluuJ9fHY8q
- Target viewport: 320 × 360 pt
- Compared states: Volume List, Scanning, Ready to Eject, Review Processes, Scan Failed

## Checks

- Header, 260 pt content area, and 56 pt action footer align with the Figma frames.
- Background, 8 pt corner radius, banner outlines, card spacing, and button widths match the reference.
- Primary actions use `#0066CC`; secondary actions use a white adaptive surface with a neutral outline.
- Volume selection, explicit scan, per-process selection, cancel/retry, and eject confirmation are functional.
- Physical-disk scope and affected-volume disclosure remain visible before ejection.
- Accessibility labels and live status announcements are present for the core flow.
- The five reference screenshots were compared side by side with runtime captures at the same viewport.

## Intentional Runtime Differences

- Runtime screenshots use the mounted disk's real name, capacity, identifier, and paths instead of Figma mock data.
- SwiftUI renders the native San Francisco system font; Figma's export may fall back to Inter.
- The selected volume has a blue selection treatment so the row's interactive state is unambiguous.

## Verification

- `xcodebuild test -project SSD_Remover.xcodeproj -scheme SSD_Remover -destination 'platform=macOS' -derivedDataPath .tmp/DerivedData CODE_SIGNING_ALLOWED=NO`
- 166 tests in 24 suites passed.
- Final runtime comparison artifacts are stored under `.tmp/figma-vs-implementation-*.png` and remain untracked.
