# Button hover/pressed states — reference

**Update (confirmed via View code):** `Label@2.5.1` **does** support `HoverFill`
and `PressedFill` in the Code View schema. Those two are now **baked into every
button** in `paste/*.controls.yaml`, so the hover/press background effect comes
through paste automatically — there is normally **nothing to do by hand**.

What the modern Label does **not** support (absent from Studio's View code, so
they cannot be pasted or even set to persist): `HoverColor`, `PressedColor`,
`HoverBorderColor`, `PressedBorderColor`. Button **text and border colour stay
constant** on hover; the **fill** change is the affordance. That's a control
limitation, not a paste limitation.

## Fill values baked in, by button group

| Group | Buttons | HoverFill | PressedFill |
|---|---|---|---|
| Green primary CTA | btnContinue, btnConfirmContinue (scrForm) · btnContinueStage2 (scrReview) · btnSubmit, btnConfirmSubmit (scrQuestions) | `#00712A` | `#005A21` |
| Navy-outline | btnHome, btnKeepEditing (scrForm) · btnBackBottom (scrDetail) · btnHome (scrReview) · btnSaveDraft, btnCancelSubmit (scrQuestions) | `#EBF0F5` | `#D8E2EB` |
| Solid navy | btnHome (scrCompleted, scrOverview) | `#003C75` | `#001A33` |
| Blue text link | btnBackHome, btnRoleDetails (scrForm) · btnBackTop (scrDetail) · btnRankDetails (scrReview) · btnBackReview, btnSecDetails (scrQuestions) · btnBackHome, btnToggle (scrOverview) · btnOpenOverview (scrLanding) | `#E1F2FB` | `#C7E6F4` |
| Green link | btnOpenForm (scrLanding) | `#E4F3EA` | `#B5DEC5` |
| Withdraw | btnWithdraw (scrOverview) | `#EEF2F5` | `#DCE2E8` |

*Excluded:* `recScrim` (both overlays) — the dialog backdrop, deliberately no
hover so it doesn't read as a button. Disabled Continue/Submit don't render
hover (the disabled grey Fill wins), so the static HoverFill is harmless.

Since these paste now, a **re-paste no longer loses them** — the earlier
"re-apply after every paste" caveat is obsolete.
