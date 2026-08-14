# Contributing to Kindle Scribe Converter

Thanks for stopping by! This is a small hobby project that grew from one
person's frustration — contributions of any size are welcome. Bug reports,
ideas, translations, documentation and code all help.

## Reporting a bug

Open an issue and include:

- KSC version (see the window title / FAQ) and how you run it (`.ps1` or `.exe`)
- Windows version and PowerShell version (`$PSVersionTable.PSVersion`)
- Whether ImageMagick and Ghostscript are installed
- Steps to reproduce
- The log output from the main window (or a screenshot)

## Requesting a feature

Open an issue with the `enhancement` label, describe the workflow you have in
mind, and why the current tool doesn't cover it. Real use cases beat generic
ideas — tell us what manga/source you're working with.

## Submitting code

1. Fork the repository and create a branch (`git checkout -b feature/xyz`).
2. Make your change. Keep it focused on one thing.
3. **Language:** all user-facing strings, help texts, the FAQ and comments are
   in English since v1.24.3 — keep new strings in English.
4. **Versioning:** semantic versioning — `patch` for bugfixes, `minor` for
   features. The version string appears in the header, window title, FAQ and
   MessageBoxes.
5. Test with PowerShell 7 (`pwsh`) — the parallel worker uses
   `Start-ThreadJob` / `ForEach-Object -Parallel` (PS7+).
6. Open a pull request describing what changed and why.

## Development setup

- PowerShell 7+ (`pwsh`)
- ImageMagick (`magick`) on PATH
- Ghostscript (`gswin64c` / `gswin32c`) — only for PDF import
- .NET Desktop Runtime (WinForms)
- To build the `.exe`: [PS2EXE](https://github.com/MScholtes/PS2EXE)
  (v1.24.3 fixed the `.exe` detection)

## Code of conduct

Be nice. This project is a gift to the manga-reading community, not a
battlefield — keep discussions respectful and constructive.
