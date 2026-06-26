# Paste into Power Apps Studio, page by page (Code View)

These files let you build the app by **pasting one screen at a time** using
Studio's **Code View** (public preview). They are the paste-ready form of the
`../Src/*.pa.yaml` source — dedented to the clipboard format Studio expects
(a top-level list of controls), because the `.pa.yaml` files themselves are
read-only Git source and can't be pasted onto a page.

| File | Paste where |
|---|---|
| `App_OnStart.powerfx` | App object → **OnStart** formula bar |
| `scrLanding.controls.yaml` | the **scrLanding** screen node |
| `scrForm.controls.yaml` | the **scrForm** screen node (incl. continue overlay) |
| `scrDetail.controls.yaml` | the **scrDetail** screen node |
| `scrReview.controls.yaml` | the **scrReview** screen node |
| `scrQuestions.controls.yaml` | the **scrQuestions** screen node (incl. submit overlay) |
| `scrCompleted.controls.yaml` | the **scrCompleted** screen node |
| `scrOverview.controls.yaml` | the **scrOverview** screen node |

## One-time setup
1. **Turn on Code View.** Power Apps Studio → **Settings → Upcoming features →
   Preview** → enable **Code View** (a.k.a. "View/Paste code"). Reload Studio.
   Grant the browser **clipboard permission** the first time you paste.
2. **Create a blank canvas app**, responsive: **Settings → Display →** Scale to
   fit **Off**, Lock aspect ratio **Off**.
3. **Create the seven screens and name them exactly** (the `Navigate()` calls
   target these names — they must match):
   `scrLanding, scrForm, scrDetail, scrReview, scrQuestions, scrCompleted, scrOverview`.
4. **App properties:** set **StartScreen = `scrLanding`**, **BackEnabled = `false`**.

## Paste the App.OnStart
1. Select the **App** object (top of the tree) → property dropdown → **OnStart**.
2. Open `App_OnStart.powerfx`, copy **all** of it, paste into the formula bar.
   *(The leading `=` is already removed for the formula bar.)*
3. Right-click the **App** object → **Run OnStart** so the seed collections exist
   while you design. Re-run it whenever you reopen the app.

## Paste each screen
For every screen:
1. In the **tree view**, select the screen node (e.g. **scrForm**).
2. Right-click → **Paste code** (or **Ctrl+V**).
3. Open the matching `scr*.controls.yaml`, **Select All → Copy**, then paste.
   The whole `conRoot` container (and, for scrForm/scrQuestions, the overlay)
   is created with all its children in one go.
4. Set the **screen's own properties** (paste only creates controls, not screen
   props):
   - **Fill** = `ColorValue("#F2F5F7")` on every screen.
   - **scrQuestions → OnVisible** = `Set(varDraftSaved, false)`.

Repeat for all seven. Then **Run OnStart** again and press **Play** to test:
Landing → Form (the seeded **1 / 1** duplicate shows the amber validation) →
Continue (locks Stage 1) → Review → Stage 2 → Submit (locks) → Completed; and
**Submissions Overview** (expand a row, soft **Withdraw**).

> The `*.controls.yaml` snippets are intentionally **comment-free and use only
> block-style YAML** — Studio's Code View parser rejects `#` comments and
> single-quoted/flow values, which is what causes `PA1001 … YamlInvalidSyntax`.
> Always copy from `paste/*.controls.yaml`, **not** from `../Src/*.pa.yaml`
> (the Src files keep comments for Git/pack and won't paste).

## Likely friction & fixes
- **`PA1001 … YamlInvalidSyntax; … found invalid mapping`.** The pasted text
  contained a `#` comment, a single-quoted value, or a `{…}` flow mapping. Use
  the `paste/*.controls.yaml` files in this folder (already cleaned) — don't
  paste the `../Src` files or hand-add comments.
- **"The clipboard doesn't contain any YAML code to paste."** You must copy the
  file's **text** to the OS clipboard and paste onto a **tree node** (not the
  canvas), with browser clipboard permission granted.
- **Control type rejected on paste.** These snippets use unversioned control IDs
  (`Label`, `Classic/Button`, `Classic/DropDown`, `Classic/TextInput`,
  `GroupContainer`, `Gallery`, `Rectangle`). If your environment wants a
  version/different id, drop a control of that type on a scratch screen →
  right-click → **View code** to see the exact `Control:` id (e.g.
  `Label@2.x.y`) and match it in the snippet.
- **Duplicate control names across screens.** Studio auto-renames clashes (e.g.
  `conHeaderBar_1`). Harmless here — formulas use `Parent`/`Self`/`ThisItem`/
  variables/collections, never another control's literal name.
- **Galleries look empty / errored at design time.** They bind to the OnStart
  collections — **Run OnStart** first.
- **Data:** everything runs on the seed collections offline. To go live, repoint
  each gallery/write to Dataverse and wire identity + admin per the main
  [`../README.md`](../README.md) (sections 2–3). In-app gating is **not**
  security — apply Dataverse row-level security.

## Want a single-import instead?
Pasting is page-by-page by design. If you'd rather import the whole app at once,
use **`pac canvas pack`** to build an `.msapp` from `../Src`, or connect the
solution to this repo via **Git integration** — see [`../README.md`](../README.md)
section 4.
