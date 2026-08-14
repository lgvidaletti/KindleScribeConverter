# CHANGELOG — Kindle Scribe Converter

## v1.24.3
### Fix
* **"True" error when compiling to .exe (PS2EXE) — robust executable detection**
    * **Problem**: When converted to `.exe` with PS2EXE, the executable printed "True"/errors to the console and/or closed immediately. The previous detection (`$isExe = $MyInvocation.MyCommand.Definition -like "*.exe"`) **never matched inside a compiled `.exe`**: PS2EXE redefines `$MyInvocation` to other values, and `.Definition` points to the original script — not the `.exe`. With `$isExe = $false`, the auto-relaunch logic fired inside the executable, spuriously relaunching `pwsh -STA -File <path>` (pointing at the original script, not the `.exe`).
    * **Fix**: Robust 3-layer `.exe` detection:
        1. `$PS2EXE -eq $true` — variable set by PS2EXE inside generated executables;
        2. `$MyInvocation.MyCommand.CommandType -ne ExternalScript` — in a compiled `.exe` the command is not an external script (same technique documented by PS2EXE.Core);
        3. legacy `Definition` check kept as a fallback.
        `Start-Process` output also silenced with `| Out-Null`.
    * **Impact**: The `.exe` starts straight into the UI, with no spurious relaunch and no "True" printed to the console.
* **Fuzz: default changed to 3% + black-margin warning**
    * **Change**: Fuzz parameter default: `5%` → `3%` (defaults, UI field, help text and `~` button all restore `3%`).
    * **Warning**: The help text now states that high Fuzz values **can create black margins where they should not exist** (background areas treated as content). Keep it at `3%`.
* **Version and naming consistency**
    * **Problem**: The script still identified itself as v1.24.1 (header, Form title, FAQ, MessageBoxes) and the PDF button said "Exportar PDF" (documented naming: "Importar PDF").
    * **Fix**: All version labels updated to v1.24.3; button renamed to "Importar PDF".
* **Documentation synced**
    * **Changelog**: Reordered chronologically (newest first); v1.24.1 now consolidates the version's two real changes (PNG Feature + dynamic `$defThread` Perf) — previously the external changelog and the internal FAQ recorded different versions for the same number.
    * **Prompt Mestre**: Updated to v1.24.3 — PNG support documented, language corrected to PowerShell 7+ (Start-ThreadJob), Fuzz default 3%, duplicate BUG-15 consolidated, history updated.

---

## v1.24.2
### Fix
*   **"True" suppression and .exe auto-relaunch fix**
    *   **Problem**: Running the script directly, the `SetProcessDPIAware()` call printed "True" to the console. Also, when compiled to `.exe` with PS2EXE, the script's auto-relaunch logic caused the executable to close immediately, since it tried to relaunch itself as a PowerShell script.
    *   **Fix**: The `SetProcessDPIAware()` output was silenced with `| Out-Null`. The auto-relaunch logic was changed to detect when the script is already running as an `.exe`, disabling the unnecessary and conflicting relaunch. The executable now starts correctly without a flickering console window and without closing unexpectedly.
    *   **Impact**: Better UX when running the script directly (no "True") and full functionality in the `.exe` build, which now starts and operates as expected.
    *   **Note**: This version's `.exe` detection (via `Definition`) proved incomplete in PS2EXE executables — finished in v1.24.3 (`$PS2EXE` + `CommandType`).

---

## v1.24.1
### Feature
* **PNG file support**
    * **Change**: The script now accepts and processes `.png` images in addition to `.jpg` and PDF. All file scans use `Get-ChildItem -Include *.jpg, *.png` (Spreads popup, normal processing and flat mode).
    * **Impact**: More flexibility for users with PNG manga or images. Output remains standardized as JPG (`_upscale.jpg` / sequential numbering) for Kindle Scribe compatibility.

### Perf
* **Dynamic `$defThread` based on CPU**
    * **Change**: Default thread count now computed as `[math]::Max(2, [int]($cpuCount * 0.75))` instead of a fixed 6.
    * **Examples**: 4-core CPU → 3 | 8-core → 6 | 16-core → 12. Minimum of 2 guaranteed on 1–2 core machines.

---

## v1.24.0
### Perf
* **Consolidate 5 magick pre-analysis calls into 1 (magick calls per image: 6 -> 2)**
    * **Context**: Since v1.9.3, the worker ran 5 separate spawns (1 for dimensions + 4 for corners) before the main pipeline.
    * **Problem**: Each spawn meant a process fork plus disk load, adding up to ~1000 processes on 200-image batches.
    * **Fix**: Replaced the 5 spawns with a single ImageMagick call using parenthetical clones (`'(' +clone ... +delete ')'`).
    * **Gain**: Drastic call reduction (6 to 2 per image), with performance gains proportional to volume.
    * **Safe fallback**: If the call fails, neutral thresholds are assumed to avoid a crash.

---

## v1.23.1
### Fix
* **Forced relaunch for any PS < 7 in the STA AUTO-RELAUNCH block**
    * **Problem**: PowerShell 5.1 runs in STA by default, so the previous relaunch condition never fired and the script tried to run on an incompatible version.
    * **Consequence**: `TerminatingError` failures around line ~1980, because `Start-ThreadJob` does not exist in PS 5.1.
    * **Fix**: Added a version check (`Major -lt 7`) to force relaunching with `pwsh -STA`.

---

## v1.23.0
### Feature
* **PS7 parallelism — RunspacePool replaced by Start-ThreadJob + ForEach-Object -Parallel**
    * **Change**: All parallel workers now use PowerShell 7's native threading infrastructure.
    * **Management**: Simplified cancellation via `Stop-Job` and polling via `Receive-Job` (keeping WinForms responsive).
    * **Efficiency**: `[scriptblock]::Create()` allows passing code between runspaces without heavy serialization and cuts ~25 lines of boilerplate per section.

---

## v1.22.0
### PowerShell 5 → PowerShell 7 migration
* **STA auto-relaunch**: `ApartmentState` detection at the top of the script to guarantee STA execution on PS7.
* **Native settings**: `$PSNativeCommandErrorActionPreference = 'Ignore'` to manage native-command exceptions on PS7.2+.
* **Encoding & styles**: Forced UTF-8 on the console and modern visual styles for WinForms.
* **Dependencies**: Added .NET Desktop Runtime presence check with a direct download link on failure.

---

## v1.21.2 — v1.21.1
### UI and responsiveness tweaks
* **Layout refinement**: Pixel-level nudges on the logo, wider thread control, removal of idle footer space.
* **Responsiveness**: Dynamic `AutoScroll` for small screens and DPI awareness to avoid blur at high resolutions.

---

## v1.20.4
### Fix
* **UI clipping**: FAQ/About button clipping and header alignment fixed.
* **Dynamic FAQ repositioning** to avoid clipping.
* **Removed incorrect window size restrictions**.

---

## v1.19.0
### Control redesign (FF-06)
* **Modernization**: The `~` character on reset buttons replaced by the new `forward.png` icon.
* **Portability**: Icon embedded as Base64 to keep the script a single file.
* **Visual feedback**: Buttons turn blue (`#00A8E1`) when active to signal changes.

---

## v1.14.3
### Encoding fix
* **Character cleanup**: Fixed multibyte UTF-8 characters that corrupted the parser on PowerShell 5.1.
* **Optimization**: File size reduced from 652 KB to 103 KB after removing encoding "junk".
* **Identification**: File now saved with **UTF-8 BOM** for explicit system recognition.

---

## v1.14.2 — v1.14.0
### UX and flow improvements
* **File identification**: Extraction status now shows the name of the PDF being processed in real time.
* **Cancel button**: Safe interruption during processing, with a visual transition to a red button.
* **Spread control**: Simplified click instructions and a safety warning when switching folders to prevent lost configuration.
* **Completion metrics**: Added a timer showing total processing time in the log and final status.

---

## v1.13.0
### UX
* **Folder dialog modernized** — `OpenFileDialog` (same as the PDF dialog).
* **Level simplified** — White dial removed; only Black dial, 5% step.
* **Import PDF button** — name confirmed (was "Exportar PDF").

---

## v1.12.1
### Fix BUG-14
* `$script:SpreadPairs` did not persist after the Spreads popup.
* **Cause**: PS5.1 enumerates `List[object]` on function return; 1 pair → single object (no `.Count`); 0 pairs → null.
* **Fix**: `btnConf` copies pairs straight into `$script:SpreadPairs` and sets `$popup.Tag = $true` (bool); callers read `$script:SpreadPairs.Count`.

---

## v1.12.0
### Feature FF-05
* New "Process later" PDF flow — instant 72 DPI preview, Spreads popup opens immediately, user tweaks parameters freely, then PROCESS extracts at real DPI + remaps spreads + runs the pipeline in one click.

---

## v1.11.0
### Feature FF-04
* "Process later" flow now opens the Spreads popup automatically after PDF extraction — user configures spreads without extra manual steps.

---

## v1.10.0
### Fix BUG-13
* Spreads failed to merge (corrupted paths: pg1=D, pg2=empty).

---

## v1.9.4
### Fix BUG-12 — Spreads popup ran out of memory with large images (PDF export)
* **Cause**: Thumbnails were loaded as Bitmaps at FULL resolution (e.g. 1500×2250px = ~12.8 MB per image in 32-bit ARGB). A 200+ page manga = ~2.5 GB of RAM → silent `OutOfMemoryException` (swallowed by try/catch) → the popup showed no images, which looked like "cannot find spreads to merge".
* **Fix**: Thumbnails now load pre-resized to 100×126px (~50 KB each); memory for 200 pages drops from ~2.5 GB to ~10 MB.
* **Bonus**: `magick +append` now captures stderr and logs the detailed error on failure; `_spreads_temp` folder creation has explicit error handling (`-Force` + try/catch).

---

## v1.9.3
### Fix BUG-11 — white margin added by `-extent` on black-background pages
* **Cause**: Background detection used only the NW corner (5×5px); if bright content sat in the NW corner but the real background was black, bg=white → `-extent` filled unwanted white borders.
* **Fix**: Average of the 4 corners (NW, NE, SW, SE); one bright corner does not "win" alone; threshold > 0.5 = white, ≤ 0.5 = black.
* **Magick calls per image**: 3 → 6 (1 identify + 4 corner crops + 1 pipeline).

---

## v1.9.2
### Fix BUG-10 — spreads placed at the end instead of their original position (flat mode)
* **Cause**: `$allFiles = @($sortedRegular) + $validSpreadItems` always appended spreads at the end.
* **Fix**: Flat mode now sorts ALL files (including the spread source pages), determines each pair's natural position and inserts the spread in place of the page that appears first in the sort order; the second page is discarded; position preserved.

---

## v1.9.1
### Fix BUG-09 — PDF page count
* **Fixed**: `identify` with `[0]` returned `%n=1` (only 1 page extracted).
* **Fix**: `magick identify -ping` without a frame index; `Count` of lines = real total.

---

## v1.9.0
### Feature FF-02 — PDF import
* **"Import PDF"** button on the input folder line.
* Custom dark popup with PDF picker and DPI field (default 300, range 72–1200).
* `?` button explains the 150/200/300 DPI difference for each PDF type.
* Ghostscript check before extracting (`gswin64c` / `gswin32c`).
* Page count via: `magick identify -format "%n" "pdf[0]"`.
* Parallel extraction via Start-ThreadJob (reuses the UI Threads config).
* PDFWorkerBlock: `magick -density DPI "pdf[N]" -quality 90 "page_XXXX.jpg"`.
* No processing parameters applied (resize, gray, level, unsharp, contrast).
* Output: `<pdf-name>_pages\` next to the PDF file.
* Input folder auto-filled + SpreadPairs cleared after completion.
* Completion MessageBox with page count and output path.

---

## v1.8.1
### Fix BUG-08
* `GetNewClosure` + `$script:` in WinForms handler; Spreads popup instruction text revised.

---

## v1.8.0
### Feature FF-01 — Spreads (double pages)
* First implementation of double-page spread pairing and merging.
