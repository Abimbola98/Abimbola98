# Button hover/pressed states — set manually in Studio

Confirmed 22/07/2026: `Hover*`/`Pressed*` properties are **not part of the
Code View (pa.yaml) schema** in this environment — Studio's own View code
omits them even when set, and pasted values are silently dropped (the
properties fall back to their defaults, `Self.Fill`/`Self.Color`). They can
only be set **in Studio**. The values persist in the saved app; they just
never appear in Code View.

> ⚠️ Consequence: **re-pasting a screen wipes these settings** for the
> replaced controls — re-apply from this sheet after any re-paste.

## How to apply quickly

Per screen, **Ctrl+click** every button of the same style in the tree view to
multi-select, then set each property once for the whole selection (property
dropdown → paste the formula). Buttons inside a gallery template (marked *gal*)
are set once on the template and apply to every row.

For **borderless** buttons (all links + green CTAs + solid navy) the two
`*BorderColor` rows are optional — `BorderThickness` is 0 so they never show.

## 1 · Green primary CTAs
`btnContinue`, `btnConfirmContinue` (scrForm) · `btnContinueStage2` (scrReview)
· `btnSubmit`, `btnConfirmSubmit` (scrQuestions)

| Property | Formula |
|---|---|
| HoverFill | `ColorValue("#00712A")` |
| PressedFill | `ColorValue("#005A21")` |
| HoverColor | `ColorValue("#FFFFFF")` |
| PressedColor | `ColorValue("#FFFFFF")` |

## 2 · Navy-outline buttons
`btnHome`, `btnKeepEditing` (scrForm) · `btnBackBottom` (scrDetail) ·
`btnHome` (scrReview) · `btnSaveDraft`, `btnCancelSubmit` (scrQuestions)

| Property | Formula |
|---|---|
| HoverFill | `ColorValue("#EBF0F5")` |
| PressedFill | `ColorValue("#D8E2EB")` |
| HoverColor | `ColorValue("#002B54")` |
| PressedColor | `ColorValue("#002B54")` |
| HoverBorderColor | `ColorValue("#002B54")` |
| PressedBorderColor | `ColorValue("#002B54")` |

## 3 · Solid navy Home buttons
`btnHome` (scrCompleted) · `btnHome` (scrOverview)

| Property | Formula |
|---|---|
| HoverFill | `ColorValue("#003C75")` |
| PressedFill | `ColorValue("#001A33")` |
| HoverColor | `ColorValue("#FFFFFF")` |
| PressedColor | `ColorValue("#FFFFFF")` |

## 4 · Blue text links
`btnBackHome`, `btnRoleDetails` *(gal)* (scrForm) · `btnBackTop` (scrDetail) ·
`btnRankDetails` *(gal)* (scrReview) · `btnBackReview`, `btnSecDetails` *(gal)*
(scrQuestions) · `btnBackHome`, `btnToggle` *(gal)* (scrOverview) ·
`btnOpenOverview` (scrLanding)

| Property | Formula |
|---|---|
| HoverFill | `ColorValue("#E1F2FB")` |
| PressedFill | `ColorValue("#C7E6F4")` |
| HoverColor | `ColorValue("#0A5580")` |
| PressedColor | `ColorValue("#063E5D")` |

## 5 · Green link — `btnOpenForm` (scrLanding)

| Property | Formula |
|---|---|
| HoverFill | `ColorValue("#E4F3EA")` |
| PressedFill | `ColorValue("#B5DEC5")` |
| HoverColor | `ColorValue("#00712A")` |
| PressedColor | `ColorValue("#005A21")` |

## 6 · Withdraw — `btnWithdraw` *(gal)* (scrOverview)

| Property | Formula |
|---|---|
| HoverFill | `ColorValue("#EEF2F5")` |
| PressedFill | `ColorValue("#DCE2E8")` |
| HoverColor | `ColorValue("#002B54")` |
| PressedColor | `ColorValue("#002B54")` |
| HoverBorderColor | `ColorValue("#002B54")` |
| PressedBorderColor | `ColorValue("#002B54")` |

*Deliberately excluded:* `recScrim` (both overlays) — it's the dialog
backdrop, not a button; hover states would wrongly advertise it as clickable.
