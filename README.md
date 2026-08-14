# Kindle Scribe Converter

![License](https://img.shields.io/badge/license-MIT-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-7%2B-5391FE)
![Platform](https://img.shields.io/badge/platform-Windows-blue)
![ImageMagick](https://img.shields.io/badge/ImageMagick-required-orange)
![GitHub stars](https://img.shields.io/github/stars/lgvidaletti/KindleScribeConverter)
![GitHub release](https://img.shields.io/github/v/release/lgvidaletti/KindleScribeConverter)

A PowerShell + ImageMagick tool that prepares manga for the original **Kindle Scribe (2022)** model:
resizes every page to the exact screen resolution (300 DPI, 2480×1860), cleans
up the image (grayscale, contrast, sharpening), merges double-page spreads and
outputs sequentially numbered JPGs ready for **Kindle Create**.

> **The short version:** your manga pages must already be the size of the
> Scribe's screen. If they are not, the Scribe scales them and you get blur.
> This tool makes every page exactly 2480×1860 — and nothing else in my flow
> did that the way I wanted.

---

## Screenshots

![Kindle Scribe Converter UI](screenshot.png)

*Main window with the spread-pairing popup (manga read right-to-left).*

---

## The story (why this exists)

The Kindle Scribe has a **huge** 10.2-inch e-ink screen at **300 DPI**
(2480×1860 px). That is both its best feature and its biggest problem for
manga: the screen is so large that any mismatch between the page and the
screen resolution is immediately visible as **softness, blur and gray-ish
washed-out tones**.

Manga files come in very different quality tiers:

| Source | Typical quality |
|---|---|
| **Humble Bundle** collections | Print-ready, true 300 DPI PDFs — genuinely excellent |
| **Official digital releases** (Viz Media sold through Kobo, Amazon, Barnes & Noble) | Far from that quality — downscaled, compressed, sometimes oddly proportioned |
| **Scanned/pirated sources** (Hakuneko and similar scrapers) | Even worse — inconsistent resolution, dirty backgrounds, gray pages |

I won't pretend I know everything about every source. What I can guarantee is
this: **this tool was written by someone who was desperate** — someone who
wanted to read manga on a large screen using a cheap device, the Kindle
Scribe.

**KCC alone was not enough for me** — not for my workflow, and not for my
taste. I went through several other tools and scripts until I found a
combination that *visually* worked. The core discovery was simple:

> The Scribe's screen is enormous, so pages that are not configured to the
> Scribe's exact size get scaled by the device — and **that scaling is the
> blur**. Once I matched the page proportions to the screen (2480×1860),
> I finally had something I could actually read comfortably.

An honest note: for *official* and *pirated* manga, reading on a smaller
screen (phone, tablet, older Kindle) is **objectively better** — the flaws
are simply less visible there. This tool exists for the Scribe experience:
making the most of a big, cheap, high-DPI screen.

---

## What it does

1. **Smart resizing** — detects each page's orientation and resizes it to the
   exact Kindle Scribe resolution (300 DPI):
   - Landscape pages → **2480×1860**
   - Portrait pages → **1860×2480**
   - Uses the Lanczos filter (best upscaling quality) and fills the borders
     with the page's real background color.

2. **Automatic background detection** — samples the 4 corners of the image
   (5×5 px each) and averages them to decide white vs. black background,
   so flashbacks and gray pages are handled correctly (fix v1.9.3/BUG-11).

3. **Manga-oriented contrast correction**
   - Grayscale conversion *before* processing (the Scribe is monochrome
     e-ink; chroma is ignored by the hardware → ~30% faster encode,
     ~40–50% smaller files).
   - Contrast-Stretch 0.5%×0.5% (automatic, no UI).
   - **Level** to remap black/white points — essential for gray-ish scans.
   - **Unsharp Mask** to enhance edges and line art.

4. **Double-page spreads** — click two thumbnails to merge them into a single
   landscape page (with RTL support for manga read right-to-left).

5. **PDF import** — rasterizes PDF pages via Ghostscript with configurable DPI
   (150/200/300), with a fast preview mode for setting up spreads.

6. **Parallel processing** — Start-ThreadJob with a configurable thread count
   (default: CPU × 0.75).

7. **Two output layouts** — keep your chapter folder structure, or flatten
   everything into sequentially numbered files for Kindle Create.

---

## Requirements

- **Windows 10/11** with **PowerShell 5.1+** (PowerShell 7 recommended for
  full parallel performance; the script auto-relaunches into PS7 if present).
- **ImageMagick** (free): <https://imagemagick.org/script/download.php#windows>
- **Ghostscript** — *required only for PDF import*:
  <https://www.ghostscript.com/releases/gsdnld.html>
- **.NET Desktop Runtime** for Windows (WinForms dependency):
  <https://dotnet.microsoft.com/download/dotnet>
- **Kindle Create** (free, from Amazon) — only needed for the final `.kpf`
  step of Workflow 2: <https://www.amazon.com/kindle-dbs/fd_kcp>
- **Calibre** (free) + the **KFX Output** plugin — only needed to convert
  `.kpf` → `.kfx` in Workflow 2: <https://calibre-ebook.com/download> ·
  plugin: <https://www.mobileread.com/forums/showthread.php?t=272290>

## Installation

1. Download `KindleScribeConverter_v1_24_3.ps1` (or clone this repo).
2. Install ImageMagick (and Ghostscript if you use PDFs).
3. Open PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\KindleScribeConverter_v1_24_3.ps1
```

> Optionally compile it to a standalone `.exe` with
> [PS2EXE](https://github.com/MScholtes/PS2EXE) so it runs without a console
> and without touching execution policies (v1.24.3 fixed exe detection).

---

## Usage

KSC has two output layouts — choose the one that matches **how you will
finish the manga**:

- **With Chapters** → `output\` keeps your chapter/volume folder structure —
  use this when you will finish the book in **KCC (Kindle Comic Converter)**.
- **Kindle Create** → `output_kc\` flattens everything into sequential
  numbers — use this when you will finish the book in **Kindle Create**
  (`.kpf`) and convert it to KFX with Calibre (`.kfx`).

### Workflow 1 — With Chapters → finish in KCC (Kindle Comic Converter)

1. Click **Folder...** and select the root folder containing your manga images
   (`.jpg` / `.png`, any subfolder structure).
2. *(Optional)* Click **Configure Spreads** to merge double pages.
3. Adjust parameters if needed (defaults work well).
4. Click **PROCESS IMAGES** → choose **With Chapters**.
5. Output goes to `output\` preserving your chapter/volume subfolders —
   import that folder into **Kindle Comic Converter (KCC)** to produce the
   final file for your Scribe.

> Only choose **With Chapters** if you are finishing in KCC. For the Kindle
> Create flow (`.kpf` → `.kfx`) use Workflow 2 instead.

### Workflow 2 — Kindle Create + Calibre (final `.kfx`, official or pirated manga)

All images are copied into a single `output_kc\` folder with sequential
numbering (`0001.jpg`, `0002.jpg`, ...) — the exact format **Kindle Create**
reads correctly. Finish the book with Kindle Create + the **KFX Output**
plugin of Calibre:

**Official manga (e.g. Humble Bundle EPUBs):**

1. From the EPUB, extract the `image` folder containing the manga images.
2. Open that folder in KSC and make the adjustments you want.
3. Click **PROCESS IMAGES** → choose **Kindle Create**.
4. Open the KSC `output_kc\` folder in **Kindle Create** and create a `.kpf`
   file (you can include a table of contents).
5. Run the **KFX Output** inside the manga folder. The plugin must already be installed in **Calibre** to convert `.kpf` to KFX.
6. Rename the file (e.g. `manga.kfx`) and send it to your **Kindle Scribe**.

**Pirated/scanned manga:**

1. Open your manga folder directly in KSC and make the adjustments you want.
2. Click **PROCESS IMAGES** → choose **Kindle Create**.
3. Open the KSC `output_kc\` folder in **Kindle Create** and create a `.kpf`
   file (you can include a table of contents).
4. Run the **KFX Output** inside the manga folder. The plugin must already be installed in **Calibre** to convert `.kpf` to KFX.
5. Rename the file and send it to your **Kindle Scribe**.

> Tip: the **With Chapters** export already keeps chapter organization by
> volume folders — so if you prefer finishing in **KCC** instead of the
> Kindle Create flow, use Workflow 1.

### Workflow 3 — PDF import (two modes)

Click **Import PDF**, pick a file and set the extraction DPI:

- **Process later (default)** — extracts a fast 72 DPI preview, opens the
  Spreads popup immediately so you can pair double pages, then lets you tweak
  parameters. When you click **PROCESS IMAGES**, it re-extracts at the real
  DPI, re-maps your spreads and runs the full pipeline in one step.
- **Extract images** — extracts directly at the real DPI with no processing
  (images go to `<pdf-name>_pages\` next to the PDF).

**DPI guidance:** 300 DPI for high-quality physical scans, 200 DPI for
digital/vector PDFs (faster, smaller), 150 DPI when speed matters most.

---

## Parameters

| Parameter | Default | What it does |
|---|---|---|
| **Fuzz** | **3%** | Color tolerance for background detection. **Always keep at 3%.** High values can create black margins where they should not exist (background areas treated as content). Reserved for future use. |
| **Sharpness** | 0.7 | Unsharp Mask strength (`0x0.6+amount+0.02`). Range 0.5–1.0. |
| **Level** | 0%,100% | Remaps black/white points (`X%,Y%`). Use `10%,100%` for gray-ish manga, `10%,90%` for full correction, `0%,90%` for yellowish scans. |
| **Quality** | 85 | JPEG quality (85–100). 85 is indistinguishable from 95 on e-ink and produces smaller files. |
| **Threads** | CPU × 0.75 | Parallel workers (minimum 2; max follows your CPU). |

Each parameter has `+` / `-` dial buttons and a `~` button to restore the
default.

---

## Spreads (double pages)

- Click **Configure Spreads** to open the pairing UI (scrollable thumbnail grid).
- Click two thumbnails: **1st click = LEFT page, 2nd click = RIGHT page**.
- Manga is read right-to-left: click the **RIGHT** page first.
- Yellow = pending selection, green = confirmed pair; click a paired thumbnail
  to undo. **Clear All** resets everything, **Keep** confirms and closes.
- At processing time, each pair is merged with ImageMagick `+append` into a
  landscape page and the individual source pages are excluded.

---

## FAQ

Run the script and click **FAQ / About** — the full built-in FAQ includes the
complete changelog and background-detection/processing details.

---

## Troubleshooting

- **"ImageMagick not installed"** — install ImageMagick and restart
  PowerShell. Note: ImageMagick uses the `magick` command.
- **PDF import fails** — Ghostscript is missing or not on `PATH`. Install it
  and restart.
- **.exe shows errors and closes** — make sure you're on v1.24.3 (this
  version fixed the PS2EXE detection).
- **Compiled `.exe` crashes when importing PDFs** — PDF extraction relies on
  PowerShell 7 thread jobs (`Start-ThreadJob` / `ForEach-Object -Parallel`),
  which can be unreliable inside a classic PS2EXE build. For full PDF
  support, run the `.ps1` with `pwsh -STA -File` — or compile the `.exe`
  with a PowerShell 7 runtime ([PS2EXE](https://github.com/MScholtes/PS2EXE)).
- **Black/white margins appear where they shouldn't** — Fuzz is above 3%.

---

## Contributing

Contributions are welcome — this is a hobby project built by one person who
just wanted to read manga on a Scribe.

- **Found a bug?** Open an issue with your version, OS and the log output.
- **Have an idea?** Open a feature request.
- **Want to code?** Fork, branch, send a PR. Keep new strings in English
  (the script was fully translated in v1.24.3) and follow semantic
  versioning (patch = bugfix, minor = feature).

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT — see [LICENSE](LICENSE). Free to use, modify and redistribute.
