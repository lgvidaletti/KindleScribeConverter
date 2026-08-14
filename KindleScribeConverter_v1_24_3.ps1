
# Kindle Scribe Converter v1.24.3
# Author: Luigi Vidaletti + CREAO AI
# Description: Manga image processor for Kindle Scribe via ImageMagick
# Repository: github.com/lgvidaletti/KindleScribeConverter
# CHANGELOG v1.24.3: Fix .exe "True" (robust PS2EXE detection via $PS2EXE/CommandType -- no spurious relaunch) | Fuzz default 3% | consistent versioning | PNG docs synced

# --- STA AUTO-RELAUNCH (PS7 runs in MTA by default; WinForms requires STA) ---
# Also relaunches if PS < 7 (Start-ThreadJob/ForEach-Object -Parallel require PS7)
# Compiled .exe detection (PS2EXE): inside the executable PS2EXE redefines
# $MyInvocation to other values -- .Definition points to the ORIGINAL SCRIPT,
# not to the .exe. Therefore the legacy check (-like "*.exe") does NOT match in an .exe.
# Reliable signals: the $PS2EXE variable ($true inside PS2EXE exes) and
# $MyInvocation.MyCommand.CommandType -ne ExternalScript (in an .exe the command
# is not an external script). Fix v1.24.3 (the .exe printed "True"/errors and closed).
$isExe = $false
try { if ($PS2EXE -eq $true) { $isExe = $true } } catch {}
if (-not $isExe) { $isExe = ($MyInvocation.MyCommand.Definition -like "*.exe") }
if (-not $isExe) {
    try {
        if ($null -ne $MyInvocation.MyCommand) {
            $isExe = ($MyInvocation.MyCommand.CommandType -ne [System.Management.Automation.CommandTypes]::ExternalScript)
        }
    } catch {}
}
$needsRelaunch = -not $isExe -and (([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) -or ($PSVersionTable.PSVersion.Major -lt 7))
if ($needsRelaunch) {
    $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwsh) {
        $argList = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`"")
        Start-Process -FilePath $pwsh.Source -ArgumentList $argList -NoNewWindow -Wait | Out-Null
    } else {
        [System.Console]::Error.WriteLine('ERROR: pwsh not found. Run with: pwsh -STA -File KindleScribeConverter.ps1')
    }
    exit
}

# --- UTF-8 ENCODING (paths with special characters) ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

# --- SUPPRESS NATIVE COMMAND ERRORS (PS7.2+: non-zero exit codes would throw without this) ---
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandErrorActionPreference = 'Ignore'
}

# --- .NET DESKTOP RUNTIME CHECK (WinForms requires Windows Desktop Runtime) ---
try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
} catch {
    $errMsg  = "ERROR: .NET Desktop Runtime not found.`n`n"
    $errMsg += "Kindle Scribe Converter requires the .NET Windows Desktop Runtime.`n`n"
    $errMsg += "Install it from: https://dotnet.microsoft.com/download/dotnet`n`n"
    $errMsg += "(Choose .NET 6 or later, 'Desktop Runtime' section)"
    Write-Host $errMsg -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# --- DPI AWARENESS (prevents automatic Windows scaling; covers .ps1 and .exe) ---
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class KSC_DpiHelper {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
# Out-Null: suppresses the "True" return value that the compiled .exe (PS2EXE) console would print
try { [KSC_DpiHelper]::SetProcessDPIAware() | Out-Null } catch {}

# --- IMAGEMAGICK CHECK ---
$magickCheck = Get-Command magick -ErrorAction SilentlyContinue
if (-not $magickCheck) {
    [System.Windows.Forms.MessageBox]::Show(
        "ImageMagick was not found on this system.`n`nInstall it from: https://imagemagick.org/script/download.php#windows`n`nAfter installing, restart PowerShell and try again.",
        "ImageMagick not installed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit
}

# --- PARAMETER DEFAULTS ---
$script:ParamDefaults = @{
    ResizeH  = "2480x1860"
    ResizeV  = "1860x2480"
    Fuzz     = "3%"
    Nitidez  = "0.7"
    Contrast = "0.5%x0.5%"
    Level    = "0%,100%"
    Quality  = "85"
}

# --- TEXTOS DE AJUDA ---
$script:HelpTexts = @{
    "Fuzz"     = "FUZZ (color tolerance)`n`nDefault: 3% -- always keep it at 3%.`n`nWARNING: high values can create BLACK MARGINS`nwhere they should not exist (background areas`ntreated as content).`n`nNote: background detection uses the average of`nthe 4 corners (5x5px each, fix v1.9.3/BUG-11).`nThis parameter is reserved for future use.`n`nButtons + and - adjust by 1%.`nButton ~ restores the default value (3%)."
    "Nitidez"  = "SHARPNESS - Unsharp Mask (amount)`n`nShows only the strength of the enhancement. Recommended range: 0.5 to 1.0`nDefault: 0.7`n`nInternally uses: 0x0.6+{amount}+0.02`n  sigma 0.6 -> base blur smoothness (fixed)`n  threshold 0.02 -> only sharpens where there is real contrast (fixed)`n`nButtons + and - adjust by 0.1.`nMore aggressive: 1.0 or higher`nSmoother: 0.5`nButton ~ restores 0.7"
    "Level"    = "LEVEL (black and white remapping)`n`nFormat: X%,Y%`nDefault: 0%,100% (no change)`n`nThis is the IDEAL parameter for gray-ish manga!`n`nDIAL (v1 - black point) - 5% step`n  + raises v1: dark grays become pure black`n  - lowers v1: less dark correction`n  Example: 10%,100% -> gray-ish manga`n  Example: 15%,100% -> strong contrast`n`nTip: edit the field directly to adjust white (v2)`n  0%,90% -> scan with yellowish paper`n  10%,90% -> full correction (darks + lights)`n  0%,100% -> no change (default)"
    "Quality"  = "JPEG QUALITY (compression)`n`nRange: 85 to 100`nDefault: 85`n`nButtons + and - adjust by 5 (85 -> 90 -> 95 -> 100).`n`n85 -> ideal for Kindle Scribe (indistinguishable from 95 on E-ink, smaller file)`n95-100 -> only if you need the file for something other than the Kindle"
    "Threads"  = "PARALLEL THREADS`n`nHow many images to process at the same time.`nDefault: CPU x 0.75 (e.g. 6 for an 8-core CPU)`n`nExamples for an 8-core CPU:`n 4 -> conservative balance`n 6 -> recommended default (CPU*0.75)`n 8 -> maximum, uses the whole CPU`nMaximum adjusts to your CPU (max(8, CPU*0.75)).`n`nNumericUpDown: click + or - to adjust."
}

# --- SPREADS / PENDING PDF STATE ---
$script:SpreadPairs = [System.Collections.Generic.List[object]]::new()
$script:pendingPDF  = $null   # @{ Path; DPI; OutputDir; PreviewDir } when a PDF awaits final extraction
$script:IsRunning       = $false
$script:CancelRequested = $false
$script:ClearLogIconB64 = "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"
$script:ForwardIconB64 = "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"

# --- WORKER SCRIPTBLOCK (normal + flat processing) ---
$script:WorkerBlock = {
    param($file, $ROOT, $OUTPUT, $fuzz, $nitidez, $level, $quality, $skipExist, $overrideOutfile = "")
    # PS7.2+: suppress automatic errors on non-zero exit codes (we check $LASTEXITCODE manually)
    if ($PSVersionTable.PSVersion.Major -ge 7) { $PSNativeCommandErrorActionPreference = 'Ignore' }
    $resizeH  = "2480x1860"
    $resizeV  = "1860x2480"
    $contrast = "0.5%x0.5%"
    $result = [PSCustomObject]@{
        RelPath  = ""
        Outfile  = ""
        Orient   = ""
        Bg       = ""
        MeanVal  = 0.0
        Status   = "ok"
        ErrorMsg = ""
    }
    try {
        $filename     = [System.IO.Path]::GetFileNameWithoutExtension($file)
        $relativePath = $file.Substring($ROOT.Length).TrimStart("\", "/")
        $result.RelPath = $relativePath

        if ($overrideOutfile -and $overrideOutfile -ne "") {
            $outfile   = $overrideOutfile
            $targetDir = Split-Path $outfile -Parent
        } else {
            $dirPart = Split-Path $relativePath -Parent
            if ($dirPart -match "^[A-Z]:") { $dirPart = $dirPart.Substring(2).TrimStart("\") }
            $targetDir = if ([string]::IsNullOrWhiteSpace($dirPart)) { $OUTPUT } else { Join-Path $OUTPUT $dirPart }
            $outfile   = Join-Path $targetDir ($filename + "_upscale.jpg")
        }

        $result.Outfile = $outfile

        if ($skipExist -and (Test-Path $outfile)) {
            $result.Status = "skipped"
            return $result
        }

        # --- CALL 1/2: dims + 4 corner means in a single magick invocation ---
        # Uses parenthetical clones (+clone inside '(' ')') to get dimensions and the
        # 4 corner means without spawning 5 separate processes. Each clone block -> crop ->
        # Gray -> -write info: -> +delete; at the end -format "%wx%h" -write info: writes dims.
        # Output order: NW, NE, SW, SE, dims (5 lines).
        $rawInfo = & magick "$file" `
            '(' +clone -gravity NorthWest -crop 5x5+0+0 +repage -colorspace Gray -format "%[fx:mean]`n" -write info: +delete ')' `
            '(' +clone -gravity NorthEast  -crop 5x5+0+0 +repage -colorspace Gray -format "%[fx:mean]`n" -write info: +delete ')' `
            '(' +clone -gravity SouthWest  -crop 5x5+0+0 +repage -colorspace Gray -format "%[fx:mean]`n" -write info: +delete ')' `
            '(' +clone -gravity SouthEast  -crop 5x5+0+0 +repage -colorspace Gray -format "%[fx:mean]`n" -write info: +delete ')' `
            -format "%wx%h" -write info: -delete 0 null: 2>$null

        $cNW = $cNE = $cSW = $cSE = 0.5
        $dims = ""
        if ($rawInfo -and $rawInfo.Count -ge 5) {
            $cNW  = [double]($rawInfo[0].Trim())
            $cNE  = [double]($rawInfo[1].Trim())
            $cSW  = [double]($rawInfo[2].Trim())
            $cSE  = [double]($rawInfo[3].Trim())
            $dims = $rawInfo[4].Trim()
        }

        if ($dims -match '^(\d+)x(\d+)$') {
            $isHorizontal = [int]$Matches[1] -gt [int]$Matches[2]
        } else { $isHorizontal = $false }
        $result.Orient = if ($isHorizontal) { "Horizontal" } else { "Vertical" }

        $cornerNum = ($cNW + $cNE + $cSW + $cSE) / 4
        $bg = if ($cornerNum -gt 0.5) { "white" } else { "black" }
        $result.Bg      = $bg
        $result.MeanVal = [math]::Round($cornerNum, 3)

        if (!(Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction SilentlyContinue | Out-Null
        }

        $resizeParam = if ($isHorizontal) { $resizeH } else { $resizeV }
        $levelArgs   = @()
        if ($level -ne "0%,100%" -and $level -ne "0%, 100%") {
            $levelArgs = @("-level", $level)
        }
        $unsharpStr = "0x0.6+$nitidez+0.02"

        & magick "$file" `
            -colorspace Gray `
            -filter Lanczos `
            -resize $resizeParam `
            -background $bg `
            -gravity center `
            -extent $resizeParam `
            @levelArgs `
            -unsharp $unsharpStr `
            -contrast-stretch $contrast `
            -strip `
            -quality $quality `
            "$outfile" 2>$null

        if ($LASTEXITCODE -ne 0) {
            $result.Status   = "error"
            $result.ErrorMsg = "magick returned code $LASTEXITCODE"
        }
    } catch {
        $result.Status   = "error"
        $result.ErrorMsg = $_.Exception.Message
    }
    return $result
}

# --- PDF WORKER SCRIPTBLOCK (page extraction without processing) ---
$script:PDFWorkerBlock = {
    param($pdfPath, $outputDir, $pageIndex, $dpi)
    # PS7.2+: suppress automatic errors on non-zero exit codes (we check $LASTEXITCODE manually)
    if ($PSVersionTable.PSVersion.Major -ge 7) { $PSNativeCommandErrorActionPreference = 'Ignore' }
    $result = [PSCustomObject]@{
        Page     = $pageIndex + 1
        OutFile  = ""
        Status   = "ok"
        ErrorMsg = ""
    }
    try {
        $outFile        = Join-Path $outputDir ("page_{0:D4}.jpg" -f ($pageIndex + 1))
        $result.OutFile = $outFile
        & magick -density $dpi "$($pdfPath)[$pageIndex]" -quality 90 "$outFile" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $result.Status   = "error"
            $result.ErrorMsg = "magick returned code $LASTEXITCODE"
        }
    } catch {
        $result.Status   = "error"
        $result.ErrorMsg = $_.Exception.Message
    }
    return $result
}

# --- THREADS: CPU count and default calculation ---
$cpuCount  = [Environment]::ProcessorCount
$defThread = [math]::Max(2, [int]($cpuCount * 0.75))

# ============================================================
# --- MAIN FORM ---
# ============================================================
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Kindle Scribe Converter v1.24.3"
$form.ClientSize      = New-Object System.Drawing.Size(840, 760)
# FixedSingle already prevents resizing; do not set MinimumSize/MaximumSize equal to ClientSize.
# Those properties measure the window's outer size and reduce the usable area, clipping the FAQ.
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox     = $false
$form.MinimizeBox     = $true
$form.BackColor       = [System.Drawing.Color]::FromArgb(217, 217, 217)
$form.ForeColor       = [System.Drawing.Color]::FromArgb(51, 51, 51)

$AnchorTLR = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorTR  = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorBLR = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left  -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorBR  = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$AnchorALL = [System.Windows.Forms.AnchorStyles]::Top    -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$maxContentWidth = 1100
$panelMaxW       = $maxContentWidth + 40

$contentPanel = New-Object System.Windows.Forms.Panel
$contentPanel.Location  = New-Object System.Drawing.Point(0, 70)
$contentPanel.Size      = New-Object System.Drawing.Size(840, 690)
$contentPanel.BackColor = [System.Drawing.Color]::FromArgb(217, 217, 217)
$contentPanel.Anchor    = [System.Windows.Forms.AnchorStyles]::None
$form.Controls.Add($contentPanel)

# ============================================================
# --- HEADER PANEL (azul fixo, topo do form) ---
# ============================================================
$headerPanel                = New-Object System.Windows.Forms.Panel
$headerPanel.Location       = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size           = New-Object System.Drawing.Size(840, 70)
$headerPanel.BackColor      = [System.Drawing.Color]::FromArgb(217, 217, 217)
$headerPanel.Anchor         = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

# --- Logo KSC (canto direito do header) ---
$script:KSCLogoB64 = "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"
$kscLogoBytes  = [Convert]::FromBase64String($script:KSCLogoB64)
$kscLogoStream = New-Object System.IO.MemoryStream(,$kscLogoBytes)
$kscLogoBitmap = [System.Drawing.Bitmap]::FromStream($kscLogoStream)

$pbKSCLogo           = New-Object System.Windows.Forms.PictureBox
$pbKSCLogo.Image     = $kscLogoBitmap
$pbKSCLogo.Location  = New-Object System.Drawing.Point(14, 8)
$pbKSCLogo.Size      = New-Object System.Drawing.Size(336, 54)
$pbKSCLogo.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$pbKSCLogo.BackColor = [System.Drawing.Color]::Transparent
$headerPanel.Controls.Add($pbKSCLogo)

$form.Controls.Add($headerPanel)

# ============================================================
# --- HELPER FUNCTIONS ---
# ============================================================
function New-Label($text, $x, $y, $w = 160, $h = 24) {
    $lbl           = New-Object System.Windows.Forms.Label
    $lbl.Text      = $text
    $lbl.Location  = New-Object System.Drawing.Point($x, $y)
    $lbl.Size      = New-Object System.Drawing.Size($w, $h)
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    return $lbl
}

function New-TextBox($default, $x, $y, $w = 180, $h = 26) {
    $tb             = New-Object System.Windows.Forms.TextBox
    $tb.Text        = $default
    $tb.Location    = New-Object System.Drawing.Point($x, $y)
    $tb.Size        = New-Object System.Drawing.Size($w, $h)
    $tb.BackColor   = [System.Drawing.Color]::White
    $tb.ForeColor   = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $tb.BorderStyle = "FixedSingle"
    return $tb
}

function New-SmallButton($text, $x, $y, $bgColor) {
    $btn           = New-Object System.Windows.Forms.Button
    $btn.Location  = New-Object System.Drawing.Point($x, $y)
    $btn.Size      = New-Object System.Drawing.Size(24, 26)
    $btn.BackColor = $bgColor
    $btn.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $btn.FlatStyle = "Flat"
    if ($text -eq "~") {
        try {
            $fwBytes  = [Convert]::FromBase64String($script:ForwardIconB64)
            $fwStream = New-Object System.IO.MemoryStream(,$fwBytes)
            $fwOrig   = [System.Drawing.Image]::FromStream($fwStream)
            $fwBmp    = New-Object System.Drawing.Bitmap($fwOrig, 16, 16)
            $fwOrig.Dispose()
            $btn.Image      = $fwBmp
            $btn.ImageAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        } catch {}
    } else {
        $btn.Text = $text
    }
    return $btn
}

function New-HelpButton($tag, $x, $y) {
    $btn           = New-Object System.Windows.Forms.Button
    $btn.Text      = "?"
    $btn.Tag       = $tag
    $btn.Location  = New-Object System.Drawing.Point($x, $y)
    $btn.Size      = New-Object System.Drawing.Size(28, 26)
    $btn.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btn.ForeColor = [System.Drawing.Color]::White
    $btn.FlatStyle = "Flat"
    $btn.Add_Click({
        $key = $this.Tag
        $msg = $script:HelpTexts[$key]
        [System.Windows.Forms.MessageBox]::Show($msg, "Help - $key",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })
    return $btn
}

# ============================================================
# --- CUSTOM POP-UP: How to organize the images? ---
# ============================================================
function Show-OrganizacaoPopup($parentForm) {
    $popup                 = New-Object System.Windows.Forms.Form
    $popup.Text            = "Kindle Scribe Converter"
    $popup.ClientSize      = New-Object System.Drawing.Size(500, 310)
    $popup.StartPosition   = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox     = $false
    $popup.MinimizeBox     = $false
    $popup.BackColor       = [System.Drawing.Color]::FromArgb(217, 217, 217)
    $popup.ForeColor       = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Tag             = "cancel"

    $lblTitulo           = New-Object System.Windows.Forms.Label
    $lblTitulo.Text      = "How do you want to organize the images?"
    $lblTitulo.Location  = New-Object System.Drawing.Point(20, 18)
    $lblTitulo.Size      = New-Object System.Drawing.Size(460, 26)
    $lblTitulo.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitulo.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Controls.Add($lblTitulo)

    $sep1           = New-Object System.Windows.Forms.Label
    $sep1.Location  = New-Object System.Drawing.Point(20, 50)
    $sep1.Size      = New-Object System.Drawing.Size(460, 1)
    $sep1.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep1)

    $lbl1T           = New-Object System.Windows.Forms.Label
    $lbl1T.Text      = "OUTPUT FOLDER  With separate chapters"
    $lbl1T.Location  = New-Object System.Drawing.Point(20, 62)
    $lbl1T.Size      = New-Object System.Drawing.Size(460, 22)
    $lbl1T.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl1T.ForeColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $popup.Controls.Add($lbl1T)

    $lbl1D           = New-Object System.Windows.Forms.Label
    $lbl1D.Text      = "Keeps the original folder structure. Ideal for personal`norganization or direct reading on the Kindle. Output: output\ folder"
    $lbl1D.Location  = New-Object System.Drawing.Point(20, 86)
    $lbl1D.Size      = New-Object System.Drawing.Size(460, 36)
    $lbl1D.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lbl1D.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
    $popup.Controls.Add($lbl1D)

    $sep2           = New-Object System.Windows.Forms.Label
    $sep2.Location  = New-Object System.Drawing.Point(20, 130)
    $sep2.Size      = New-Object System.Drawing.Size(460, 1)
    $sep2.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep2)

    $lbl2T           = New-Object System.Windows.Forms.Label
    $lbl2T.Text      = "FINAL FILE  No subfolders - Kindle Create"
    $lbl2T.Location  = New-Object System.Drawing.Point(20, 140)
    $lbl2T.Size      = New-Object System.Drawing.Size(460, 22)
    $lbl2T.Font      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $lbl2T.ForeColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $popup.Controls.Add($lbl2T)

    $lbl2D           = New-Object System.Windows.Forms.Label
    $lbl2D.Text      = "Use this option to finalize your manga in Kindle Create.`nAll images go into a single folder with sequential`nnumbering (0001.jpg, 0002.jpg...) - the format Kindle`nCreate reads correctly. Output: output_kc\ folder"
    $lbl2D.Location  = New-Object System.Drawing.Point(20, 164)
    $lbl2D.Size      = New-Object System.Drawing.Size(460, 62)
    $lbl2D.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lbl2D.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
    $popup.Controls.Add($lbl2D)

    $sep3           = New-Object System.Windows.Forms.Label
    $sep3.Location  = New-Object System.Drawing.Point(20, 234)
    $sep3.Size      = New-Object System.Drawing.Size(460, 1)
    $sep3.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep3)

    $btnCh           = New-Object System.Windows.Forms.Button
    $btnCh.Text      = "WITH CHAPTERS"
    $btnCh.Location  = New-Object System.Drawing.Point(20, 246)
    $btnCh.Size      = New-Object System.Drawing.Size(152, 36)
    $btnCh.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnCh.ForeColor = [System.Drawing.Color]::White
    $btnCh.FlatStyle = "Flat"
    $btnCh.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnCh.Add_Click({ $popup.Tag = "chapters"; $popup.Close() })
    $popup.Controls.Add($btnCh)

    $btnKC           = New-Object System.Windows.Forms.Button
    $btnKC.Text      = "KINDLE CREATE"
    $btnKC.Location  = New-Object System.Drawing.Point(182, 246)
    $btnKC.Size      = New-Object System.Drawing.Size(152, 36)
    $btnKC.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnKC.ForeColor = [System.Drawing.Color]::White
    $btnKC.FlatStyle = "Flat"
    $btnKC.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnKC.Add_Click({ $popup.Tag = "flat"; $popup.Close() })
    $popup.Controls.Add($btnKC)

    $btnCa           = New-Object System.Windows.Forms.Button
    $btnCa.Text      = "Cancel"
    $btnCa.Location  = New-Object System.Drawing.Point(344, 246)
    $btnCa.Size      = New-Object System.Drawing.Size(136, 36)
    $btnCa.BackColor = [System.Drawing.Color]::FromArgb(128, 128, 128)
    $btnCa.ForeColor = [System.Drawing.Color]::White
    $btnCa.FlatStyle = "Flat"
    $btnCa.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnCa.Add_Click({ $popup.Tag = "cancel"; $popup.Close() })
    $popup.Controls.Add($btnCa)

    $popup.ShowDialog($parentForm) | Out-Null
    return $popup.Tag
}

# ============================================================
# --- SPREADS POP-UP ---
# ============================================================
function Show-SpreadsPopup($parentForm, $rootPath) {
    $jpgFiles = @(Get-ChildItem -Path $rootPath -Recurse -Include *.jpg, *.png |
        Where-Object {
            $_.FullName -notmatch "\\output\\" -and
            $_.FullName -notmatch "\\output_kc\\" -and
            $_.FullName -notmatch "\\_spreads_temp\\"
        } | Sort-Object {
            [regex]::Replace($_.FullName, '\d+', { $args[0].Value.PadLeft(10,'0') })
        })

    if ($jpgFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No .jpg or .png images found in the selected folder.",
            "No images",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $null
    }

    $script:ss_pending = $null
    $script:ss_pairs   = [System.Collections.Generic.List[object]]::new()
    $script:ss_panels  = @{}

    $popup                 = New-Object System.Windows.Forms.Form
    $popup.Text            = "Configure Spreads - Kindle Scribe Converter"
    $popup.ClientSize      = New-Object System.Drawing.Size(888, 640)
    $popup.StartPosition   = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox     = $false
    $popup.MinimizeBox     = $false
    $popup.BackColor       = [System.Drawing.Color]::FromArgb(217, 217, 217)
    $popup.ForeColor       = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Tag             = $null

    $lblTitle           = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "SPREADS - Double Pages"
    $lblTitle.Location  = New-Object System.Drawing.Point(16, 12)
    $lblTitle.Size      = New-Object System.Drawing.Size(560, 24)
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $popup.Controls.Add($lblTitle)

    $lblInstr           = New-Object System.Windows.Forms.Label
    $lblInstr.Text      = "-> 1st click: LEFT  |  2nd click: RIGHT  |  Click a pair to undo"
    $lblInstr.Location  = New-Object System.Drawing.Point(16, 46)
    $lblInstr.Size      = New-Object System.Drawing.Size(856, 18)
    $lblInstr.Font      = New-Object System.Drawing.Font("Segoe UI", 8)
    $lblInstr.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
    $popup.Controls.Add($lblInstr)

    $lblPairs           = New-Object System.Windows.Forms.Label
    $lblPairs.Text      = "No pairs configured yet."
    $lblPairs.Location  = New-Object System.Drawing.Point(16, 78)
    $lblPairs.Size      = New-Object System.Drawing.Size(856, 20)
    $lblPairs.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $lblPairs.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
    $popup.Controls.Add($lblPairs)

    $sep1           = New-Object System.Windows.Forms.Label
    $sep1.Location  = New-Object System.Drawing.Point(16, 100)
    $sep1.Size      = New-Object System.Drawing.Size(856, 1)
    $sep1.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep1)

    $flow              = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Location     = New-Object System.Drawing.Point(16, 104)
    $flow.Size         = New-Object System.Drawing.Size(856, 462)
    $flow.AutoScroll   = $true
    $flow.BackColor    = [System.Drawing.Color]::FromArgb(200, 200, 200)
    $flow.Padding      = New-Object System.Windows.Forms.Padding(4)
    $popup.Controls.Add($flow)

    $script:ss_updatePairsLabel = {
        if ($script:ss_pairs.Count -eq 0) {
            $lblPairs.Text      = "No pairs configured yet."
            $lblPairs.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
        } else {
            $txts = @()
            $n = 1
            foreach ($p in $script:ss_pairs) {
                $n1 = [System.IO.Path]::GetFileName($p.L)
                $n2 = [System.IO.Path]::GetFileName($p.R)
                $txts += "#$n : $n1 + $n2"
                $n++
            }
            $lblPairs.Text      = $txts -join "   |   "
            $lblPairs.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 180)
        }
    }

    $script:ss_setPanelState = {
        param($path, $state, $pairNum = 0, $side = "")
        $pnl = $script:ss_panels[$path]
        if ($null -eq $pnl) { return }
        switch ($state) {
            "normal" {
                $pnl.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
                $pnl.Controls["badge"].Visible = $false
            }
            "pending" {
                $pnl.BackColor = [System.Drawing.Color]::FromArgb(255, 220, 100)
                $pnl.Controls["badge"].Visible = $false
            }
            "paired" {
                $pnl.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
                $badge          = $pnl.Controls["badge"]
                $badge.Text     = "#$pairNum $side"
                $badge.Visible  = $true
            }
        }
    }

    $script:ss_renumber = {
        $n = 1
        foreach ($p in $script:ss_pairs) {
            & $script:ss_setPanelState $p.L "paired" $n "L"
            & $script:ss_setPanelState $p.R "paired" $n "R"
            $n++
        }
    }

    foreach ($f in $jpgFiles) {
        $filePath = $f.FullName

        $pnl           = New-Object System.Windows.Forms.Panel
        $pnl.Size      = New-Object System.Drawing.Size(114, 164)
        $pnl.Margin    = New-Object System.Windows.Forms.Padding(3)
        $pnl.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
        $pnl.Cursor    = [System.Windows.Forms.Cursors]::Hand
        $pnl.Tag       = $filePath

        $pb           = New-Object System.Windows.Forms.PictureBox
        $pb.Location  = New-Object System.Drawing.Point(7, 7)
        $pb.Size      = New-Object System.Drawing.Size(100, 126)
        $pb.SizeMode  = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $pb.BackColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
        $pb.Tag       = $filePath
        $pb.Cursor    = [System.Windows.Forms.Cursors]::Hand

        try {
            $fs  = [System.IO.File]::OpenRead($filePath)
            $src = [System.Drawing.Image]::FromStream($fs)
            $bmp = New-Object System.Drawing.Bitmap($src, 100, 126)
            $src.Dispose()
            $fs.Close()
            $fs.Dispose()
            $pb.Image = $bmp
        } catch {}

        $lblName           = New-Object System.Windows.Forms.Label
        $lblName.Text      = [System.IO.Path]::GetFileName($filePath)
        $lblName.Location  = New-Object System.Drawing.Point(0, 136)
        $lblName.Size      = New-Object System.Drawing.Size(114, 24)
        $lblName.Font      = New-Object System.Drawing.Font("Segoe UI", 6.5)
        $lblName.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
        $lblName.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $lblName.Tag       = $filePath
        $lblName.Cursor    = [System.Windows.Forms.Cursors]::Hand

        $badge            = New-Object System.Windows.Forms.Label
        $badge.Name       = "badge"
        $badge.Text       = ""
        $badge.Location   = New-Object System.Drawing.Point(58, 7)
        $badge.Size       = New-Object System.Drawing.Size(49, 22)
        $badge.Font       = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
        $badge.ForeColor  = [System.Drawing.Color]::White
        $badge.BackColor  = [System.Drawing.Color]::FromArgb(0, 120, 180)
        $badge.TextAlign  = [System.Drawing.ContentAlignment]::MiddleCenter
        $badge.Visible    = $false

        $pnl.Controls.Add($pb)
        $pnl.Controls.Add($lblName)
        $pnl.Controls.Add($badge)
        $badge.BringToFront()

        $script:ss_panels[$filePath] = $pnl

        $clickAction = {
            $path = $this.Tag

            $inPairIdx = -1
            for ($i = 0; $i -lt $script:ss_pairs.Count; $i++) {
                if ($script:ss_pairs[$i].L -eq $path -or $script:ss_pairs[$i].R -eq $path) {
                    $inPairIdx = $i; break
                }
            }
            if ($inPairIdx -ge 0) {
                $pair = $script:ss_pairs[$inPairIdx]
                $script:ss_pairs.RemoveAt($inPairIdx)
                & $script:ss_setPanelState $pair.L "normal"
                & $script:ss_setPanelState $pair.R "normal"
                & $script:ss_renumber
                & $script:ss_updatePairsLabel
                return
            }

            if ($script:ss_pending -eq $path) {
                $script:ss_pending = $null
                & $script:ss_setPanelState $path "normal"
                return
            }

            if ($null -eq $script:ss_pending) {
                $script:ss_pending = $path
                & $script:ss_setPanelState $path "pending"
                return
            }

            $prevPend = $script:ss_pending
            $newPair  = [PSCustomObject]@{ L = $prevPend; R = $path }
            $script:ss_pending = $null
            $script:ss_pairs.Add($newPair)
            $pNum = $script:ss_pairs.Count
            & $script:ss_setPanelState $prevPend "paired" $pNum "L"
            & $script:ss_setPanelState $path    "paired" $pNum "R"
            & $script:ss_updatePairsLabel
        }

        $pb.Add_Click($clickAction)
        $pnl.Add_Click($clickAction)
        $lblName.Add_Click($clickAction)

        $flow.Controls.Add($pnl)
    }

    $sep2           = New-Object System.Windows.Forms.Label
    $sep2.Location  = New-Object System.Drawing.Point(16, 574)
    $sep2.Size      = New-Object System.Drawing.Size(856, 1)
    $sep2.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep2)

    $btnClear           = New-Object System.Windows.Forms.Button
    $btnClear.Text      = "Clear All"
    $btnClear.Location  = New-Object System.Drawing.Point(16, 584)
    $btnClear.Size      = New-Object System.Drawing.Size(130, 36)
    $btnClear.BackColor = [System.Drawing.Color]::FromArgb(210, 70, 70)
    $btnClear.ForeColor = [System.Drawing.Color]::White
    $btnClear.FlatStyle = "Flat"
    $btnClear.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnClear.Add_Click({
        if ($null -ne $script:ss_pending) {
            & $script:ss_setPanelState $script:ss_pending "normal"
            $script:ss_pending = $null
        }
        foreach ($pair in $script:ss_pairs) {
            & $script:ss_setPanelState $pair.L "normal"
            & $script:ss_setPanelState $pair.R "normal"
        }
        $script:ss_pairs.Clear()
        & $script:ss_updatePairsLabel
    })
    $popup.Controls.Add($btnClear)

    $btnConf           = New-Object System.Windows.Forms.Button
    $btnConf.Text      = "Keep"
    $btnConf.Location  = New-Object System.Drawing.Point(622, 584)
    $btnConf.Size      = New-Object System.Drawing.Size(120, 36)
    $btnConf.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnConf.ForeColor = [System.Drawing.Color]::White
    $btnConf.FlatStyle = "Flat"
    $btnConf.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnConf.Add_Click({
        if ($null -ne $script:ss_pending) {
            & $script:ss_setPanelState $script:ss_pending "normal"
            $script:ss_pending = $null
        }
        $script:SpreadPairs = $script:ss_pairs
        $popup.Tag = $true
        $popup.Close()
    })
    $popup.Controls.Add($btnConf)

    $btnCancelS           = New-Object System.Windows.Forms.Button
    $btnCancelS.Text      = "Cancel"
    $btnCancelS.Location  = New-Object System.Drawing.Point(754, 584)
    $btnCancelS.Size      = New-Object System.Drawing.Size(118, 36)
    $btnCancelS.BackColor = [System.Drawing.Color]::FromArgb(128, 128, 128)
    $btnCancelS.ForeColor = [System.Drawing.Color]::White
    $btnCancelS.FlatStyle = "Flat"
    $btnCancelS.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnCancelS.Add_Click({
        $popup.Tag = $null
        $popup.Close()
    })
    $popup.Controls.Add($btnCancelS)

    $popup.Add_FormClosed({
        foreach ($pnl in $flow.Controls) {
            $pb2 = $pnl.Controls | Where-Object { $_ -is [System.Windows.Forms.PictureBox] } | Select-Object -First 1
            if ($pb2 -and $pb2.Image) { $pb2.Image.Dispose(); $pb2.Image = $null }
        }
        $script:ss_panels.Clear()
        $script:ss_pending = $null
    })

    $popup.ShowDialog($parentForm) | Out-Null
    return ($popup.Tag -eq $true)
}

# ============================================================
# --- PDF IMPORT POP-UP ---
# ============================================================
function Show-ImportPDFPopup($parentForm) {
    $popup                 = New-Object System.Windows.Forms.Form
    $popup.Text            = "Import PDF - Kindle Scribe Converter"
    $popup.ClientSize      = New-Object System.Drawing.Size(520, 298)
    $popup.StartPosition   = "CenterParent"
    $popup.FormBorderStyle = "FixedDialog"
    $popup.MaximizeBox     = $false
    $popup.MinimizeBox     = $false
    $popup.BackColor       = [System.Drawing.Color]::FromArgb(217, 217, 217)
    $popup.ForeColor       = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Tag             = $null

    $lblTitle           = New-Object System.Windows.Forms.Label
    $lblTitle.Text      = "Import PDF - extract images"
    $lblTitle.Location  = New-Object System.Drawing.Point(20, 16)
    $lblTitle.Size      = New-Object System.Drawing.Size(480, 26)
    $lblTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Controls.Add($lblTitle)

    $sep1           = New-Object System.Windows.Forms.Label
    $sep1.Location  = New-Object System.Drawing.Point(20, 48)
    $sep1.Size      = New-Object System.Drawing.Size(480, 1)
    $sep1.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep1)

    $lblPDF           = New-Object System.Windows.Forms.Label
    $lblPDF.Text      = "PDF file:"
    $lblPDF.Location  = New-Object System.Drawing.Point(20, 58)
    $lblPDF.Size      = New-Object System.Drawing.Size(100, 24)
    $lblPDF.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Controls.Add($lblPDF)

    $txtPDFPath             = New-Object System.Windows.Forms.TextBox
    $txtPDFPath.Location    = New-Object System.Drawing.Point(20, 82)
    $txtPDFPath.Size        = New-Object System.Drawing.Size(362, 26)
    $txtPDFPath.BackColor   = [System.Drawing.Color]::White
    $txtPDFPath.ForeColor   = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $txtPDFPath.BorderStyle = "FixedSingle"
    $popup.Controls.Add($txtPDFPath)

    $btnBrowse           = New-Object System.Windows.Forms.Button
    $btnBrowse.Text      = "Browse..."
    $btnBrowse.Location  = New-Object System.Drawing.Point(390, 80)
    $btnBrowse.Size      = New-Object System.Drawing.Size(110, 28)
    $btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnBrowse.ForeColor = [System.Drawing.Color]::White
    $btnBrowse.FlatStyle = "Flat"
    $btnBrowse.Add_Click({
        $dlg        = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "PDF files (*.pdf)|*.pdf|All files (*.*)|*.*"
        $dlg.Title  = "Select PDF file"
        if ($dlg.ShowDialog() -eq "OK") { $txtPDFPath.Text = $dlg.FileName }
    })
    $popup.Controls.Add($btnBrowse)

    $lblDPI           = New-Object System.Windows.Forms.Label
    $lblDPI.Text      = "Extraction DPI:"
    $lblDPI.Location  = New-Object System.Drawing.Point(20, 122)
    $lblDPI.Size      = New-Object System.Drawing.Size(120, 24)
    $lblDPI.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Controls.Add($lblDPI)

    $txtDPI             = New-Object System.Windows.Forms.TextBox
    $txtDPI.Text        = "300"
    $txtDPI.Location    = New-Object System.Drawing.Point(148, 120)
    $txtDPI.Size        = New-Object System.Drawing.Size(62, 26)
    $txtDPI.BackColor   = [System.Drawing.Color]::White
    $txtDPI.ForeColor   = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $txtDPI.BorderStyle = "FixedSingle"
    $popup.Controls.Add($txtDPI)

    $btnDPIHelp           = New-Object System.Windows.Forms.Button
    $btnDPIHelp.Text      = "?"
    $btnDPIHelp.Location  = New-Object System.Drawing.Point(218, 120)
    $btnDPIHelp.Size      = New-Object System.Drawing.Size(28, 26)
    $btnDPIHelp.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnDPIHelp.ForeColor = [System.Drawing.Color]::White
    $btnDPIHelp.FlatStyle = "Flat"
    $btnDPIHelp.Add_Click({
        [System.Windows.Forms.MessageBox]::Show(
            "PDF EXTRACTION DPI`n`nSets the rasterization resolution of the PDF pages.`nDefault: 300 DPI`n`n300 DPI -> ideal for high-quality physical scans`n         generates ~2480x3508px (A4) before KSC resize`n         the worker will downscale (best quality)`n`n200 DPI -> enough for digital / vector PDFs`n         resolution close to the KSC target (1860x2480px)`n         faster, smaller files`n`n150 DPI -> fast, smallest files, reduced quality`n         more upscaling in the worker`n`nFor digital (vector) manga: 200 is enough`nFor high-quality physical scans: 300 recommended",
            "Help - Extraction DPI",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    })
    $popup.Controls.Add($btnDPIHelp)

    $sep2           = New-Object System.Windows.Forms.Label
    $sep2.Location  = New-Object System.Drawing.Point(20, 160)
    $sep2.Size      = New-Object System.Drawing.Size(480, 1)
    $sep2.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep2)

    $lblModo           = New-Object System.Windows.Forms.Label
    $lblModo.Text      = "Usage mode:"
    $lblModo.Location  = New-Object System.Drawing.Point(20, 170)
    $lblModo.Size      = New-Object System.Drawing.Size(480, 20)
    $lblModo.ForeColor = [System.Drawing.Color]::FromArgb(85, 85, 85)
    $popup.Controls.Add($lblModo)

    $radioProcess           = New-Object System.Windows.Forms.RadioButton
    $radioProcess.Text      = "Process later (preview spreads + PROCESS)"
    $radioProcess.Location  = New-Object System.Drawing.Point(20, 192)
    $radioProcess.Size      = New-Object System.Drawing.Size(480, 22)
    $radioProcess.Checked   = $true
    $radioProcess.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Controls.Add($radioProcess)

    $radioExport           = New-Object System.Windows.Forms.RadioButton
    $radioExport.Text      = "Extract images"
    $radioExport.Location  = New-Object System.Drawing.Point(20, 216)
    $radioExport.Size      = New-Object System.Drawing.Size(480, 22)
    $radioExport.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $popup.Controls.Add($radioExport)

    $sep3           = New-Object System.Windows.Forms.Label
    $sep3.Location  = New-Object System.Drawing.Point(20, 246)
    $sep3.Size      = New-Object System.Drawing.Size(480, 1)
    $sep3.BackColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
    $popup.Controls.Add($sep3)

    $btnExtract           = New-Object System.Windows.Forms.Button
    $btnExtract.Text      = "EXTRACT IMAGES"
    $btnExtract.Location  = New-Object System.Drawing.Point(20, 254)
    $btnExtract.Size      = New-Object System.Drawing.Size(240, 36)
    $btnExtract.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnExtract.ForeColor = [System.Drawing.Color]::White
    $btnExtract.FlatStyle = "Flat"
    $btnExtract.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $btnExtract.Add_Click({
        $pdfVal = $txtPDFPath.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($pdfVal) -or !(Test-Path $pdfVal)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Select a valid PDF file before extracting.",
                "Invalid file",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $dpiVal = 300
        if ($txtDPI.Text -match '^\d+$') { $dpiVal = [int]$txtDPI.Text }
        if ($dpiVal -lt 72 -or $dpiVal -gt 1200) {
            [System.Windows.Forms.MessageBox]::Show(
                "DPI must be a value between 72 and 1200.",
                "Invalid DPI",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $mode = if ($radioProcess.Checked) { "process" } else { "export" }
        $popup.Tag = @{ PDFPath = $pdfVal; DPI = $dpiVal; Mode = $mode }
        $popup.Close()
    })
    $popup.Controls.Add($btnExtract)

    $btnCancelPDF           = New-Object System.Windows.Forms.Button
    $btnCancelPDF.Text      = "Cancel"
    $btnCancelPDF.Location  = New-Object System.Drawing.Point(270, 254)
    $btnCancelPDF.Size      = New-Object System.Drawing.Size(230, 36)
    $btnCancelPDF.BackColor = [System.Drawing.Color]::FromArgb(128, 128, 128)
    $btnCancelPDF.ForeColor = [System.Drawing.Color]::White
    $btnCancelPDF.FlatStyle = "Flat"
    $btnCancelPDF.Font      = New-Object System.Drawing.Font("Segoe UI", 9)
    $btnCancelPDF.Add_Click({ $popup.Tag = $null; $popup.Close() })
    $popup.Controls.Add($btnCancelPDF)

    $popup.ShowDialog($parentForm) | Out-Null
    return $popup.Tag
}

$cDec = [System.Drawing.Color]::FromArgb(160, 160, 160)
$cInc = [System.Drawing.Color]::FromArgb(160, 160, 160)
$cRst = [System.Drawing.Color]::FromArgb(160, 160, 160)

# ============================================================
# --- FOLDER SECTION ---
# ============================================================
$contentPanel.Controls.Add((New-Label "INPUT FOLDER" 20 10 300 22))

$btnPasta           = New-Object System.Windows.Forms.Button
$btnPasta.Text      = "Folder..."
$btnPasta.Location  = New-Object System.Drawing.Point(20, 36)
$btnPasta.Size      = New-Object System.Drawing.Size(100, 30)
$btnPasta.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
$btnPasta.ForeColor = [System.Drawing.Color]::White
$btnPasta.FlatStyle = "Flat"
$contentPanel.Controls.Add($btnPasta)

$txtPasta        = New-TextBox "" 130 38 520 28
$txtPasta.Anchor = $AnchorTLR
$contentPanel.Controls.Add($txtPasta)

$btnImportPDF           = New-Object System.Windows.Forms.Button
$btnImportPDF.Text      = "Import PDF"
$btnImportPDF.Location  = New-Object System.Drawing.Point(660, 36)
$btnImportPDF.Size      = New-Object System.Drawing.Size(160, 30)
$btnImportPDF.Anchor    = $AnchorTR
$btnImportPDF.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
$btnImportPDF.ForeColor = [System.Drawing.Color]::White
$btnImportPDF.FlatStyle = "Flat"
$contentPanel.Controls.Add($btnImportPDF)

# ============================================================
# --- SPREADS AND ORGANIZATION SECTION ---
# ============================================================
$btnSpreads           = New-Object System.Windows.Forms.Button
$btnSpreads.Text      = "Configure Spreads"
$btnSpreads.Location  = New-Object System.Drawing.Point(20, 80)
$btnSpreads.Size      = New-Object System.Drawing.Size(160, 30)
$btnSpreads.BackColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
$btnSpreads.ForeColor = [System.Drawing.Color]::White
$btnSpreads.FlatStyle = "Flat"
$btnSpreads.Enabled   = $false
$contentPanel.Controls.Add($btnSpreads)

$lblSpreadsStatus           = New-Object System.Windows.Forms.Label
$lblSpreadsStatus.Text      = "No spreads configured"
$lblSpreadsStatus.Location  = New-Object System.Drawing.Point(190, 85)
$lblSpreadsStatus.Size      = New-Object System.Drawing.Size(400, 20)
$lblSpreadsStatus.ForeColor = [System.Drawing.Color]::Gray
$contentPanel.Controls.Add($lblSpreadsStatus)


$chkSkip           = New-Object System.Windows.Forms.CheckBox
$chkSkip.Text      = "Skip already processed images"
$chkSkip.Location  = New-Object System.Drawing.Point(320, 120)
$chkSkip.Size      = New-Object System.Drawing.Size(300, 24)
$chkSkip.Checked   = $true
$chkSkip.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
$contentPanel.Controls.Add($chkSkip)

# --- Click: Select Folder ---
$btnPasta.Add_Click({
    $dlg                      = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description          = "Select the root folder containing the manga images"
    $dlg.ShowNewFolderButton  = $false

    if ($dlg.ShowDialog() -eq "OK") {
        $selectedPath = $dlg.SelectedPath.TrimEnd('\')
        
        if ($script:SpreadPairs.Count -gt 0) {
            $cSp = $script:SpreadPairs.Count
            $resp = [System.Windows.Forms.MessageBox]::Show(
                "There are $cSp spread pair(s) configured.`n`n-> Changing the folder will clear all spreads.`n`nContinue?",
                "Spreads configured",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($resp -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        }
        $txtPasta.Text = $selectedPath
        $script:SpreadPairs         = [System.Collections.Generic.List[object]]::new()
        $lblSpreadsStatus.Text      = "No spreads configured"
        $lblSpreadsStatus.ForeColor = [System.Drawing.Color]::Gray
    }
})

# --- Click: Configure Spreads ---
$btnSpreads.Add_Click({
    $ROOT_S = $txtPasta.Text.TrimEnd("\")
    if ([string]::IsNullOrWhiteSpace($ROOT_S) -or !(Test-Path $ROOT_S)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Select a valid folder before configuring spreads.",
            "No folder selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Show-SpreadsPopup $form $ROOT_S | Out-Null
    $c = $script:SpreadPairs.Count
    if ($c -eq 0) {
        $lblSpreadsStatus.Text      = "No spreads configured"
        $lblSpreadsStatus.ForeColor = [System.Drawing.Color]::Gray
    } else {
        $lblSpreadsStatus.Text      = "$c pair(s) configured"
        $lblSpreadsStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
    }
})

# --- TextChanged: txtPasta -> enables/disables btnSpreads ---
$txtPasta.Add_TextChanged({
    $p = $txtPasta.Text.Trim().TrimEnd("\")
    $btnSpreads.Enabled = (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path $p -PathType Container))
})

# --- Click: Import PDF ---
$btnImportPDF.Add_Click({
    # 1. Ghostscript check
    $gsFound = (Get-Command gswin64c -ErrorAction SilentlyContinue) -or
               (Get-Command gswin32c -ErrorAction SilentlyContinue)
    if (-not $gsFound) {
        [System.Windows.Forms.MessageBox]::Show(
            "Ghostscript was not found on this system.`n`nGhostscript is required for ImageMagick to read PDF files.`n`nInstall the latest version from:`nhttps://www.ghostscript.com/releases/gsdnld.html`n`nAfter installing, restart PowerShell and try again.",
            "Ghostscript not installed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # 2. Configuration popup
    $pdfConfig = Show-ImportPDFPopup $form
    if ($null -eq $pdfConfig) { return }

    $pdfPath          = $pdfConfig.PDFPath
    $dpi              = $pdfConfig.DPI
    $script:pdfMode   = $pdfConfig.Mode

    # 3. Count pages
    $pdfFileDisplay = [System.IO.Path]::GetFileName($pdfPath)
    $lblStatus.Text = "Reading pages: $pdfFileDisplay..."
    $form.Refresh()
    $identLines = @(& magick identify -ping "$pdfPath" 2>$null)
    $pageCount  = $identLines.Count
    if ($pageCount -le 0) {
        $lblStatus.Text = "Waiting..."
        [System.Windows.Forms.MessageBox]::Show(
            "Could not determine the number of pages in the PDF.`n`nCheck that the file is a valid PDF and that Ghostscript is installed correctly.",
            "Error reading PDF",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # 4. Final output folder: <pdf-name>_pages next to the PDF
    $pdfDir    = [System.IO.Path]::GetDirectoryName($pdfPath)
    $pdfName   = [System.IO.Path]::GetFileNameWithoutExtension($pdfPath)
    $safeName  = $pdfName -replace '[^\w\-]', '_'
    $outputDir = Join-Path $pdfDir "${safeName}_pages"

    # For "process" mode: extracts 72 DPI preview to a temp folder; outputDir created later by PROCESS
    # For "export" mode:  extracts directly into outputDir at real DPI (v1.11.0 behavior)
    if ($script:pdfMode -eq "process") {
        $extractDPI = 72
        $guidPart   = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
        $extractDir = Join-Path $env:TEMP "ksc_pdf_preview_$guidPart"
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
    } else {
        $extractDPI = $dpi
        $extractDir = $outputDir
        if (!(Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir | Out-Null }
    }

    # Store for use in the timer and in pendingPDF
    $script:pdfPath_imp   = $pdfPath
    $script:pdfDPI_imp    = $dpi
    $script:pdfOutputDir  = $outputDir
    $script:pdfPreviewDir = $extractDir
    $script:pdfFileName   = [System.IO.Path]::GetFileName($pdfPath)

    # 5. Log and UI
    $txtLog.Clear()
    Write-Log "=== PDF Import ===" "Cyan"
    Write-Log "File    : $pdfPath" "Gray"
    Write-Log "Pages   : $pageCount" "Cyan"
    if ($script:pdfMode -eq "process") {
        Write-Log "Real DPI    : $dpi (used when PROCESSING)" "Cyan"
        Write-Log "Preview DPI : $extractDPI (for spread selection)" "Yellow"
        Write-Log "Preview at  : $extractDir" "Gray"
        Write-Log "Final output: $outputDir" "Gray"
    } else {
        Write-Log "DPI     : $dpi" "Cyan"
        Write-Log "Output  : $outputDir" "Gray"
        Write-Log "No processing parameters applied at this stage." "Yellow"
    }
    Write-Log "----------------------------------------------" "Gray"

    $progressBar.Maximum = $pageCount
    $progressBar.Value   = 0
    $lblStatus.Text      = if ($script:pdfMode -eq "process") { "Generating preview: $($script:pdfFileName)" } else { "Extracting: $($script:pdfFileName)" }

    & $script:EnterRunMode

    # 6. PS7: Start-ThreadJob + ForEach-Object -Parallel for parallel extraction
    $nThreads    = [int]$numThreads.Value
    $pdfWorkerSrc = $script:PDFWorkerBlock.ToString()
    $pageIndices  = 0..($pageCount - 1)
    $script:pdfBatchJob = Start-ThreadJob -ScriptBlock {
        param($indices, $workerSrc, $pdfPath, $extractDir, $extractDPI, $nThreads)
        $indices | ForEach-Object -Parallel {
            $wb     = [scriptblock]::Create($using:workerSrc)
            $result = & $wb $using:pdfPath $using:extractDir $_ $using:extractDPI
            $result
        } -ThrottleLimit $nThreads
    } -ArgumentList $pageIndices, $pdfWorkerSrc, $pdfPath, $extractDir, $extractDPI, $nThreads

    $script:pdfCountOK    = 0
    $script:pdfCountError = 0
    $script:pdfTotalJobs  = $pageCount
    $script:pdfDone       = $false

    $script:pdfPollTimer          = New-Object System.Windows.Forms.Timer
    $script:pdfPollTimer.Interval = 300
    $script:pdfPollTimer.Add_Tick({
        if ($script:CancelRequested -and -not $script:pdfDone) {
            $script:pdfDone = $true
            $script:pdfPollTimer.Stop()
            Stop-Job  $script:pdfBatchJob -ErrorAction SilentlyContinue
            Remove-Job $script:pdfBatchJob -ErrorAction SilentlyContinue
            Write-Log "PDF extraction cancelled by user." "Yellow"
            $lblStatus.Text    = "Cancelled."
            $progressBar.Value = 0
            & $script:ExitRunMode
            return
        }

        $newR = @(Receive-Job -Job $script:pdfBatchJob -ErrorAction SilentlyContinue)
        foreach ($result in $newR) {
            if ($null -eq $result -or $null -eq $result.Status) { continue }
            if ($result.Status -eq "error") {
                $script:pdfCountError++
                Write-Log "[ERROR] Page $($result.Page): $($result.ErrorMsg)" "Red"
            } else {
                $script:pdfCountOK++
                $fn = [System.IO.Path]::GetFileName($result.OutFile)
                Write-Log "[OK] Page $($result.Page) -> $fn" "White"
            }
        }

        $done = $script:pdfCountOK + $script:pdfCountError
        $progressBar.Value = [math]::Min($progressBar.Maximum, $done)
        $lblStatus.Text    = "$($script:pdfFileName) -- $done / $($script:pdfTotalJobs) | Errors: $($script:pdfCountError)"

        if ($script:pdfBatchJob.State -in @('Completed','Failed','Stopped') -and -not $script:pdfDone) {
            $script:pdfDone = $true
            $script:pdfPollTimer.Stop()
            # Drain remaining results
            $tail = @(Receive-Job -Job $script:pdfBatchJob -ErrorAction SilentlyContinue)
            foreach ($result in $tail) {
                if ($null -eq $result -or $null -eq $result.Status) { continue }
                if ($result.Status -eq "error") {
                    $script:pdfCountError++
                    Write-Log "[ERROR] Page $($result.Page): $($result.ErrorMsg)" "Red"
                } else {
                    $script:pdfCountOK++
                    $fn = [System.IO.Path]::GetFileName($result.OutFile)
                    Write-Log "[OK] Page $($result.Page) -> $fn" "White"
                }
            }
            Remove-Job $script:pdfBatchJob -ErrorAction SilentlyContinue
            $progressBar.Value = $progressBar.Maximum

            & $script:ExitRunMode

            if ($script:pdfMode -eq "process") {
                # v1.12.0: preview extracted -- open spreads popup with the previews
                $lblStatus.Text = "Preview ready. Configuring spreads..."
                Write-Log "===============================================" "Cyan"
                Write-Log "PREVIEW READY: $($script:pdfCountOK) pages | $($script:pdfCountError) errors" "Lime"
                Write-Log "Opening spread configuration..." "Cyan"

                Show-SpreadsPopup $form $script:pdfPreviewDir | Out-Null
                $cPairs = $script:SpreadPairs.Count
                if ($cPairs -eq 0) {
                    $lblSpreadsStatus.Text      = "No spreads configured"
                    $lblSpreadsStatus.ForeColor = [System.Drawing.Color]::Gray
                } else {
                    $lblSpreadsStatus.Text      = "$cPairs pair(s) configured"
                    $lblSpreadsStatus.ForeColor = [System.Drawing.Color]::FromArgb(0, 140, 60)
                }

                # Create an empty outputDir so PROCESS passes the Test-Path validation
                if (!(Test-Path $script:pdfOutputDir)) {
                    New-Item -ItemType Directory -Path $script:pdfOutputDir | Out-Null
                }

                # Save pendingPDF state
                $script:pendingPDF = @{
                    Path       = $script:pdfPath_imp
                    DPI        = $script:pdfDPI_imp
                    OutputDir  = $script:pdfOutputDir
                    PreviewDir = $script:pdfPreviewDir
                }

                # Fill txtPasta with the final destination (not the preview dir)
                $txtPasta.Text = $script:pdfOutputDir

                Write-Log "Final output: $($script:pdfOutputDir)" "Cyan"
                Write-Log "Spreads configured: $cPairs pair(s)" "Cyan"
                Write-Log "===============================================" "Cyan"
                $lblStatus.Text = "PDF ready. $cPairs spread(s). Adjust the parameters and click PROCESS."

                [System.Windows.Forms.MessageBox]::Show(
                    "Preview ready!`n`nPages detected   : $($script:pdfTotalJobs)`nSpreads configured: $cPairs pair(s)`n`nNow you can adjust the parameters (Level, Sharpness, Quality etc.)`nand click PROCESS IMAGES.`n`nThe PDF will be extracted at $($script:pdfDPI_imp) DPI and processed in a single step.",
                    "Kindle Scribe Converter v1.24.3",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null

            } else {
                # "Extract images" mode: identical behavior to v1.11.0
                $lblStatus.Text = "Export complete! $($script:pdfCountOK) pages | $($script:pdfCountError) errors"
                Write-Log "===============================================" "Cyan"
                Write-Log "EXTRACTION COMPLETE: $($script:pdfCountOK) pages | $($script:pdfCountError) errors" "Lime"
                Write-Log "Images at: $($script:pdfOutputDir)" "Gray"
                Write-Log "===============================================" "Cyan"
                Write-Log "Mode: Extract images -- input folder unchanged." "Yellow"
                [System.Windows.Forms.MessageBox]::Show(
                    "Export complete!`n`nPages exported : $($script:pdfCountOK)`nErrors          : $($script:pdfCountError)`n`nImages at:`n$($script:pdfOutputDir)",
                    "Kindle Scribe Converter v1.24.3",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
            }
        }
    })
    $script:pdfPollTimer.Start()
})

# ============================================================
# --- PARAMETERS SECTION ---
# ============================================================
$lblParamTitle = New-Label "IMAGE PARAMETERS" 20 130 400 22
$lblParamTitle.ForeColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
$lblParamTitle.Font      = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$contentPanel.Controls.Add($lblParamTitle)

$paramY    = 160
$paramStep = 38

# --- Fuzz ---
$contentPanel.Controls.Add((New-Label "Fuzz:" 20 $paramY 120 24))
$txtFuzz = New-TextBox "3%" 210 $paramY 100 26
$contentPanel.Controls.Add($txtFuzz)
$capTb = $txtFuzz; $capDef = "3%"
$b = New-SmallButton "-" 178 $paramY $cDec
$b.Add_Click(({ if ($capTb.Text -match '^([\d.]+)%$') { $v=[math]::Max(0,[math]::Round([double]$Matches[1]-1,1)); $capTb.Text="${v}%" } }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "+" 150 $paramY $cInc
$b.Add_Click(({ if ($capTb.Text -match '^([\d.]+)%$') { $v=[math]::Min(100,[math]::Round([double]$Matches[1]+1,1)); $capTb.Text="${v}%" } }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "~" 320 $paramY $cRst
$b.Enabled   = $false
$b.BackColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$b.Add_Click(({ $capTb.Text=$capDef }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$bCapRst=$b; $bCapDef=$capDef; $bCapTb=$capTb
$bCapTb.Add_TextChanged(({ $en=($bCapTb.Text -ne $bCapDef); $bCapRst.Enabled=$en; if($en){ $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(0,168,225) } else { $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(210,210,210) } }.GetNewClosure()))
$contentPanel.Controls.Add((New-HelpButton "Fuzz" 354 $paramY))
$paramY += $paramStep

# --- Nitidez ---
$contentPanel.Controls.Add((New-Label "Sharpness:" 20 $paramY 120 24))
$txtNitidez = New-TextBox "0.7" 210 $paramY 100 26
$contentPanel.Controls.Add($txtNitidez)
$capTb = $txtNitidez; $capDef = "0.7"
$b = New-SmallButton "-" 178 $paramY $cDec
$b.Add_Click(({ $v=[math]::Max(0,[math]::Round([double]($capTb.Text -replace '[^0-9.]','')-0.1,2)); $capTb.Text="$v" }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "+" 150 $paramY $cInc
$b.Add_Click(({ $v=[math]::Round([double]($capTb.Text -replace '[^0-9.]','')+0.1,2); $capTb.Text="$v" }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "~" 320 $paramY $cRst
$b.Enabled   = $false
$b.BackColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$b.Add_Click(({ $capTb.Text=$capDef }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$bCapRst=$b; $bCapDef=$capDef; $bCapTb=$capTb
$bCapTb.Add_TextChanged(({ $en=($bCapTb.Text -ne $bCapDef); $bCapRst.Enabled=$en; if($en){ $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(0,168,225) } else { $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(210,210,210) } }.GetNewClosure()))
$contentPanel.Controls.Add((New-HelpButton "Nitidez" 354 $paramY))
$paramY += $paramStep

# --- Level ---
$lblLevel           = New-Label "Level:" 20 $paramY 120 24
$lblLevel.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
$contentPanel.Controls.Add($lblLevel)
$txtLevel = New-TextBox "0%,100%" 210 $paramY 100 26
$contentPanel.Controls.Add($txtLevel)
$capTb = $txtLevel; $capDef = "0%,100%"
$b = New-SmallButton "-" 178 $paramY $cDec
$b.Add_Click(({ if ($capTb.Text -match '^([\d.]+)%,([\d.]+)%$') { $v1=[math]::Max(0,[math]::Round([double]$Matches[1]-5,0)); $v2=[double]$Matches[2]; $capTb.Text="$([int]$v1)%,$([int]$v2)%" } }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "+" 150 $paramY $cInc
$b.Add_Click(({ if ($capTb.Text -match '^([\d.]+)%,([\d.]+)%$') { $v1=[math]::Round([double]$Matches[1]+5,0); $v2=[double]$Matches[2]; if($v2-$v1-lt 1){$v1=[math]::Max(0,[int]$v2-1)}; $capTb.Text="$([int]$v1)%,$([int]$v2)%" } }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "~" 320 $paramY $cRst
$b.Enabled   = $false
$b.BackColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$b.Add_Click(({ $capTb.Text=$capDef }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$bCapRst=$b; $bCapDef=$capDef; $bCapTb=$capTb
$bCapTb.Add_TextChanged(({ $en=($bCapTb.Text -ne $bCapDef); $bCapRst.Enabled=$en; if($en){ $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(0,168,225) } else { $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(210,210,210) } }.GetNewClosure()))
$contentPanel.Controls.Add((New-HelpButton "Level" 354 $paramY))
$paramY += $paramStep

# --- Quality ---
$contentPanel.Controls.Add((New-Label "Quality:" 20 $paramY 120 24))
$txtQuality = New-TextBox "85" 210 $paramY 100 26
$contentPanel.Controls.Add($txtQuality)
$capTb = $txtQuality; $capDef = "85"
$b = New-SmallButton "-" 178 $paramY $cDec
$b.Add_Click(({ try { $v=[math]::Max(85,[int]$capTb.Text-5); $capTb.Text="$v" } catch {} }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "+" 150 $paramY $cInc
$b.Add_Click(({ try { $v=[math]::Min(100,[int]$capTb.Text+5); $capTb.Text="$v" } catch {} }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$b = New-SmallButton "~" 320 $paramY $cRst
$b.Enabled   = $false
$b.BackColor = [System.Drawing.Color]::FromArgb(210, 210, 210)
$b.Add_Click(({ $capTb.Text=$capDef }.GetNewClosure()))
$contentPanel.Controls.Add($b)
$bCapRst=$b; $bCapDef=$capDef; $bCapTb=$capTb
$bCapTb.Add_TextChanged(({ $en=($bCapTb.Text -ne $bCapDef); $bCapRst.Enabled=$en; if($en){ $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(0,168,225) } else { $bCapRst.BackColor=[System.Drawing.Color]::FromArgb(210,210,210) } }.GetNewClosure()))
$contentPanel.Controls.Add((New-HelpButton "Quality" 354 $paramY))
$paramY += $paramStep + 6

# --- Threads ---
    $contentPanel.Controls.Add((New-Label "Threads:" 20 $paramY 120 24))
    $numThreads           = New-Object System.Windows.Forms.NumericUpDown
    $numThreads.Location  = New-Object System.Drawing.Point(150, $paramY)
    $numThreads.Size      = New-Object System.Drawing.Size(160, 26)
    $numThreads.Minimum   = 0
    $numThreads.Maximum   = [math]::Max(8, $defThread)
    $numThreads.Value     = $defThread
    $numThreads.BackColor = [System.Drawing.Color]::White
    $numThreads.ForeColor = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $contentPanel.Controls.Add($numThreads)
    
    $b = New-SmallButton "~" 320 $paramY $cRst
    $b.Add_Click({ $numThreads.Value = $defThread })
    $contentPanel.Controls.Add($b)
    $contentPanel.Controls.Add((New-HelpButton "Threads" 354 $paramY))
# --- PROCESS BUTTON ---
    $paramY += 45
    $btnProcessar           = New-Object System.Windows.Forms.Button
    $btnProcessar.Text      = "PROCESS IMAGES"
    $btnProcessar.Location  = New-Object System.Drawing.Point(20, $paramY)
    $btnProcessar.Size      = New-Object System.Drawing.Size(800, 45)
    $btnProcessar.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnProcessar.ForeColor = [System.Drawing.Color]::White
    $btnProcessar.FlatStyle = "Flat"
    $btnProcessar.Font      = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $contentPanel.Controls.Add($btnProcessar)
    $paramY += 55

# ============================================================
# --- STATUS + PROGRESS + LOG ---
# ============================================================
$lblStatus           = New-Object System.Windows.Forms.Label
$lblStatus.Text      = "Status: Waiting..."
$lblStatus.Location  = New-Object System.Drawing.Point(20, $paramY)
$lblStatus.Size      = New-Object System.Drawing.Size(600, 20)
$lblStatus.Anchor    = $AnchorTLR
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(102, 102, 102)
$lblStatus.Font      = New-Object System.Drawing.Font("Consolas", 8)
$contentPanel.Controls.Add($lblStatus)
$paramY += 26

$progressBar          = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, $paramY)
$progressBar.Size     = New-Object System.Drawing.Size(800, 22)
$progressBar.Anchor   = $AnchorTLR
$progressBar.Minimum  = 0
$progressBar.Value    = 0
$contentPanel.Controls.Add($progressBar)
    $lblPercent = New-Label "0%" 785 $paramY 50 22
    $contentPanel.Controls.Add($lblPercent)
$paramY += 32

$lblLog          = New-Label "LOG" 20 $paramY 36 20
$lblLog.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$contentPanel.Controls.Add($lblLog)

$btnClearLog                               = New-Object System.Windows.Forms.Button
$btnClearLog.Location                      = New-Object System.Drawing.Point(58, $paramY)
$btnClearLog.Size                          = New-Object System.Drawing.Size(22, 20)
$btnClearLog.FlatStyle                     = "Flat"
$btnClearLog.BackColor                     = [System.Drawing.Color]::FromArgb(217, 217, 217)
$btnClearLog.FlatAppearance.BorderSize     = 0
$btnClearLog.Cursor                        = [System.Windows.Forms.Cursors]::Hand
try {
    $clBytes  = [Convert]::FromBase64String($script:ClearLogIconB64)
    $clStream = New-Object System.IO.MemoryStream(,$clBytes)
    $clOrig   = [System.Drawing.Image]::FromStream($clStream)
    $clBmp    = New-Object System.Drawing.Bitmap($clOrig, 16, 16)
    $clOrig.Dispose()
    $btnClearLog.Image      = $clBmp
    $btnClearLog.ImageAlign = [System.Drawing.ContentAlignment]::MiddleCenter
} catch {}
$btnClearLog.Add_Click({ $txtLog.Clear() })
$ttClear = New-Object System.Windows.Forms.ToolTip
$ttClear.SetToolTip($btnClearLog, "Clear Log")
$contentPanel.Controls.Add($btnClearLog)

$paramY += 22

$txtLog            = New-Object System.Windows.Forms.RichTextBox
$txtLog.Location   = New-Object System.Drawing.Point(20, $paramY)
$txtLog.Size       = New-Object System.Drawing.Size(800, 150)
$txtLog.Anchor     = $AnchorALL
$txtLog.ReadOnly   = $true
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(248, 248, 248)
$txtLog.ForeColor  = [System.Drawing.Color]::FromArgb(51, 51, 51)
$txtLog.Font       = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.ScrollBars = "Vertical"
$contentPanel.Controls.Add($txtLog)
$paramY += 155

$btnFAQ           = New-Object System.Windows.Forms.Button
$btnFAQ.Text      = "FAQ / About"
$btnFAQ.Location  = New-Object System.Drawing.Point(20, $paramY)
$btnFAQ.Size      = New-Object System.Drawing.Size(150, 30)
$btnFAQ.BackColor = [System.Drawing.Color]::FromArgb(160, 160, 160)
$btnFAQ.ForeColor = [System.Drawing.Color]::White
$btnFAQ.FlatStyle = "Flat"
$contentPanel.Controls.Add($btnFAQ)

# ============================================================
# --- FAQ ---
# ============================================================
$faqText = @'
Kindle Scribe Converter v1.24.3
==========================

WHY DOES THIS SCRIPT EXIST?
The Kindle Scribe has a high-resolution e-ink screen (300 DPI), but most
manga files come with low resolution, incorrect proportions, gray-ish tones
and dirty backgrounds.
This script was created to solve exactly these problems.

WHAT DOES IT DO?

1. SMART RESIZING
   - Detects the orientation of each image (horizontal or vertical)
   - Resizes to the exact Kindle Scribe resolution (300 DPI)
   - Uses the Lanczos filter, the best algorithm for image upscaling
   - Centers with extent and fills borders with the real background color

2. AUTOMATIC BACKGROUND DETECTION (v1.9.3 - 4-corner detection, BUG-11)
   - Samples the 4 image corners (5x5px: NW, NE, SW, SE) and averages them
   - Average > 0.5 -> white background | Average <= 0.5 -> black background
   - A single bright corner does not "win" by itself (fix BUG-11)
   - Robust against flashbacks: gray page with black border is detected correctly

3. CONTRAST CORRECTION FOR MANGA
   - Contrast-Stretch: 0.5%x0.5% fixed (applied automatically, no UI)
   - Level: remaps black and white points (ESSENTIAL for gray-ish manga)
   - Unsharp Mask: enhances edges and line art

4. HIGH-QUALITY COMPRESSION
   - Colorspace Gray: converts to grayscale before processing
     (Kindle Scribe is monochrome E-ink -- chroma is ignored by the hardware)
     Result: ~30% faster encoding, ~40-50% smaller files
   - Configurable Quality (default 85 -- ideal for E-ink)

5. PARALLEL PROCESSING (v1.1.0; PS7 since v1.23.0)
   - Start-ThreadJob + ForEach-Object -Parallel with configurable N threads
   - Timer on the main thread for polling without freezing the UI

6. RESPONSIVE AND CENTERED WINDOW (v1.2.0 ~ v1.5.0)
   - Maximize / Minimize enabled
   - Content centered horizontally (max width 1100px)

7. PARAMETER DIALS (v1.7.0 / v1.7.2)
   - Button + increments the parameter value
   - Button - decrements the parameter value
   - Button ~ restores the default value
   - Level: single dial (v1 - black point), 5% step (v1.13.0)
     The white (v2) can be adjusted manually in the text field

8. OUTPUT ORGANIZATION (v1.7.8)
   - Custom pop-up asks how to organize before processing
   - WITH CHAPTERS: keeps subfolder structure -> output\
   - KINDLE CREATE: all images in one folder, sequential numbering -> output_kc\

9. SPREADS -- DOUBLE PAGES (v1.8.0)
   - Click "Configure Spreads" to open the pair selection UI
   - Scrollable thumbnail grid with all images in the folder
   - Click two thumbnails to form a pair (spread)
   - 1st click = LEFT page | 2nd click = RIGHT page
   - Manga RTL (right-to-left): click the RIGHT page first
   - Yellow = pending selection | Green = confirmed pair
   - Click a paired thumbnail to undo the pair
   - "Clear All" removes all pairs at once
   - When processing: pairs are merged via ImageMagick (+append) before the pipeline
   - The original pages of each pair are excluded from individual processing
   - WITH CHAPTERS mode: spreads go to output\spreads\spread_001.jpg...
   - KINDLE CREATE mode: spreads get regular sequential numbering
   - Temp files (_spreads_temp\) are removed at the end of processing

10. PDF IMPORT (v1.9.0)
   - "Import PDF" button on the input folder line
   - Requires Ghostscript installed (https://www.ghostscript.com/releases/gsdnld.html)
   - Popup with file picker and DPI field (default: 300)
   - DPI 300 -> ideal for high-quality physical scans
   - DPI 200 -> enough for digital/vector PDFs
   - Parallel extraction using the same threads configured in the UI
   - No processing parameters applied at this stage
   - Images saved to <pdf-name>_pages\ next to the PDF file
   - Input folder updated automatically after extraction
   - "Process later" mode (v1.12.0):
     * Extracts a fast 72 DPI preview for spread selection
     * Spreads popup opens immediately with the previews
     * Adjust parameters freely before clicking PROCESS
     * PROCESS extracts at real DPI, remaps spreads and processes everything
   - "Extract images" mode: extracts directly at real DPI (no processing)

HOW TO USE?
1. FOLDER FLOW:
   a. Click "Select Folder" and choose the manga root folder
   b. (Optional) Configure spreads by clicking "Configure Spreads"
   c. Adjust parameters if needed (defaults work well)
   d. For gray-ish manga: set Level to 10%,90%
   e. Click "PROCESS IMAGES"
   f. Choose: WITH CHAPTERS (subfolders) or KINDLE CREATE (flat)

2. PDF FLOW (Process later mode - v1.12.0):
   a. Click "Import PDF" and select the PDF file + DPI
   b. Select "Process later" and click EXTRACT IMAGES
   c. 72 DPI preview is generated quickly
   d. Spreads popup opens -- configure pairs or cancel
   e. Form returns to normal: adjust Level, Sharpness, Quality etc.
   f. Click "PROCESS IMAGES" -- the script extracts at real DPI,
      remaps the spreads and processes everything in a single step

   PDF FLOW (Extract images mode):
   a. Click "Import PDF", select the PDF file
   b. Select "Extract images" and wait for the extraction
   c. Images saved to <pdf-name>_pages\ (input folder unchanged)

DEPENDENCIES
- ImageMagick (free): https://imagemagick.org/script/download.php#windows
- Ghostscript (required for PDF): https://www.ghostscript.com/releases/gsdnld.html
- PowerShell 5.1+ (already on Windows 10/11)

CHANGELOG

v1.24.3 - Fix: .exe (PS2EXE) printed "True"/errors and closed
          Robust executable detection via $PS2EXE and
          MyCommand.CommandType (Definition does not match in .exe)
          Fix: Fuzz default 3% (was 5%) + black margin warning
          Fix: consistent versioning (v1.24.3) + "Import PDF" button
v1.24.2 - Fix: SetProcessDPIAware "True" silenced (| Out-Null)
          Attempted .exe detection via Definition (incomplete)
v1.24.1 - Feature: .png file support (input .jpg + .png)
          Perf: dynamic $defThread based on CPU
          Before: fixed at 6; now: [math]::Max(2, [int]($cpuCount * 0.75))
          4-core CPU -> default 3 | 8-core -> 6 | 16-core -> 12
          Minimum of 2 guaranteed on 1-2 core machines

v1.24.0 - Perf: consolidate 5 magick pre-analysis calls into 1
          Magick calls per image: 6 -> 2 (was: 1 identify + 4 corner crops + 1 pipeline)
          Now: 1 call with parenthetical clones (+clone/+delete/info:) gets
          dimensions and 4 corner means; second call = processing pipeline
          On 200-image batches: ~800 fewer process spawns

v1.23.1 - Fix: forced relaunch for any PS < 7 in the STA AUTO-RELAUNCH block
          PS5.1 runs in STA by default -- previous condition skipped the relaunch
          Start-ThreadJob/ForEach-Object -Parallel do not exist in PS5.1

v1.20.4 - Fix: UI clipping of FAQ/About button and header alignment.
          Fix: dynamic FAQ repositioning to avoid clipping.
          Fix: removal of incorrect window size restrictions.
v1.13.0 - UX: Folder dialog modernized -- OpenFileDialog (same as the PDF dialog)
          UX: Level simplified -- White dial removed; only Black dial, 5% step
          UX: Import PDF button -- name confirmed (was Export PDF)
v1.12.1 - Fix BUG-14: $script:SpreadPairs did not persist after the Spreads popup
          Cause: PS5.1 enumerates List[object] on function return; 1 pair -> single object
          (no .Count); 0 pairs -> null. Fix: btnConf copies pairs into $script:SpreadPairs
          directly and sets $popup.Tag = $true (bool); callers read $script:SpreadPairs.Count
v1.12.0 - FF-05: new PDF flow "Process later" mode -- instant 72 DPI preview
          opens the Spreads popup immediately; user adjusts parameters freely;
          PROCESS extracts at real DPI + remap spreads + pipeline in 1 click
v1.11.0 - FF-04: "Process later" flow opens the Spreads popup automatically
          after PDF extraction; user configures spreads without extra manual steps
v1.10.0 - Fix BUG-13: spreads failed to merge (corrupted paths pg1=D pg2=empty)
v1.9.4 - Fix BUG-12: Spreads popup ran out of memory with large images (PDF export)
   - Cause: thumbnails loaded as Bitmap at FULL resolution (e.g. 1500x2250px =
     ~12.8 MB per image in 32-bit ARGB). A manga with 200+ pages = ~2.5 GB of
     RAM -> OutOfMemoryException silenced by try/catch -> popup showed no images
     and the user saw it as "cannot find a spread to merge"
   - Fix: thumbnails loaded pre-resized to 100x126px (~50 KB each);
     memory for 200 pages drops from ~2.5 GB to ~10 MB
   - Bonus: magick +append now captures stderr and logs the detailed error on failure;
     _spreads_temp folder creation has explicit error handling (-Force + try/catch)

v1.9.3 - Fix BUG-11: white margin added by -extent on black-background pages
   - Cause: background detection used only the NW corner (5x5px); if bright content
     sat in the NW corner but the real background was black, bg=white -> -extent filled
     with unwanted white on the borders
   - Fix: average of the 4 corners (NW, NE, SW, SE); a bright corner does not
     "win" alone; threshold > 0.5 = white, <= 0.5 = black
   - Magick calls per image: 3 -> 6 (1 identify + 4 corner crops + 1 pipeline)

v1.9.2 - Fix BUG-10: spreads placed at the end instead of the original position (flat mode)
   - Cause: $allFiles = @($sortedRegular) + $validSpreadItems always appended spreads at the end
   - Fix: flat mode now sorts ALL files (including the spread source pages),
     determines the natural position of each pair and inserts the spread in place of the
     page that appears first in the sort order; the second page is discarded; position preserved

v1.9.1 - Fix BUG-09: PDF page count
   - Fixed: identify with [0] returned %n=1 (only 1 page extracted)
   - Fix: magick identify -ping without frame index; Count of lines = real total

v1.9.0 - FF-02: PDF import
   - "Import PDF" button on the input folder line
   - Custom dark popup with PDF picker and DPI field (default 300, range 72-1200)
   - ? button explains the difference between 150/200/300 DPI for each PDF type
   - Ghostscript check before trying to extract (gswin64c / gswin32c)
   - Page count via: magick identify -format "%n" "pdf[0]"
   - Parallel extraction via Start-ThreadJob (reuses the UI Threads config)
   - PDFWorkerBlock: magick -density DPI "pdf[N]" -quality 90 "page_XXXX.jpg"
   - No processing parameters applied (resize, gray, level, unsharp, contrast)
   - Output: <pdf-name>_pages\ next to the PDF file
   - Input folder auto-filled + SpreadPairs cleared after completion
   - Completion MessageBox with page count and output path

v1.8.1 - Fix BUG-08 (GetNewClosure + $script: in WinForms handler)
         UX Spreads popup instruction text revised

v1.8.0 - FF-01: Spreads (double pages)
   - Scrollable thumbnail UI for manual spread pair selection
   - Grid with all .jpg/.png in the folder (FlowLayoutPanel with AutoScroll)
   - Click two thumbnails -> forms a pair (yellow = pending, green = pair)
   - Click a paired thumbnail -> undoes pair; automatic renumbering
   - "Clear All" button removes all configured pairs
   - When processing: magick +append merges each pair -> landscape image
   - The individual pages of each pair are excluded from normal processing
   - WITH CHAPTERS mode: spreads saved to output\spreads\spread_001.jpg...
   - KINDLE CREATE mode: spreads inserted at the end of the numbered sequence
   - Automatic cleanup of the _spreads_temp\ folder after completion
   - Selecting a new folder automatically clears the configured spreads
   - Main window: height 680 -> 718 (accommodates the Spreads row in the UI)

v1.7.10 - Processing pipeline optimization
   - -colorspace Gray added at the start of the pipeline (before resize)
   - Removed -define jpeg:dct-method=float and -sampling-factor 4:4:4
   - Magick calls per image: 4 -> 3 (global mean call removed)
   - Parallel threads: default CPU/2 -> CPU*0.75

v1.7.9 - ResizeH/V and Contrast removed from the UI, hardcoded in the worker
v1.7.8 - Custom organization pop-up + flat mode for Kindle Create
v1.7.7 - Kindle Create mode removed (temporarily)
v1.7.6 - BUG-06 AHK + BUG-07 stuck focus
v1.7.0 - Kindle Create TOC + Dials UI
v1.6.0 - Skip warning + confirmation
v1.5.x - Scope and here-string fixes
v1.0.0 - Initial version

LICENSE
MIT License - use, modify and distribute freely.
'@

$btnFAQ.Add_Click({
    $faqForm             = New-Object System.Windows.Forms.Form
    $faqForm.Text        = "Kindle Scribe Converter v1.24.3 - FAQ and Documentation"
    $faqForm.ClientSize  = New-Object System.Drawing.Size(740, 640)
    $faqForm.MinimumSize = New-Object System.Drawing.Size(500, 400)
    $faqForm.StartPosition   = "CenterParent"
    $faqForm.FormBorderStyle = "Sizable"
    $faqForm.MaximizeBox     = $true
    $faqForm.BackColor       = [System.Drawing.Color]::FromArgb(217, 217, 217)

    $faqBox            = New-Object System.Windows.Forms.RichTextBox
    $faqBox.Text       = $faqText
    $faqBox.Location   = New-Object System.Drawing.Point(10, 10)
    $faqBox.Size       = New-Object System.Drawing.Size(720, 580)
    $faqBox.Anchor     = $AnchorALL
    $faqBox.ReadOnly   = $true
    $faqBox.BackColor  = [System.Drawing.Color]::FromArgb(248, 248, 248)
    $faqBox.ForeColor  = [System.Drawing.Color]::FromArgb(51, 51, 51)
    $faqBox.Font       = New-Object System.Drawing.Font("Consolas", 9)
    $faqBox.ScrollBars = "Vertical"
    $faqForm.Controls.Add($faqBox)

    $btnClose           = New-Object System.Windows.Forms.Button
    $btnClose.Text      = "Close"
    $btnClose.Location  = New-Object System.Drawing.Point(300, 598)
    $btnClose.Size      = New-Object System.Drawing.Size(140, 32)
    $btnClose.Anchor    = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $btnClose.BackColor = [System.Drawing.Color]::FromArgb(128, 128, 128)
    $btnClose.ForeColor = [System.Drawing.Color]::White
    $btnClose.FlatStyle = "Flat"
    $btnClose.Add_Click({ $faqForm.Close() })
    $faqForm.Controls.Add($btnClose)

    $faqForm.ShowDialog() | Out-Null
})

# ============================================================
# --- LOG FUNCTION ---
# ============================================================
function Write-Log($msg, $color = "LightGray") {
    $colorMap = @{
        "Cyan"      = [System.Drawing.Color]::FromArgb(0, 95, 138)
        "Lime"      = [System.Drawing.Color]::FromArgb(0, 110, 50)
        "Green"     = [System.Drawing.Color]::FromArgb(0, 120, 55)
        "Yellow"    = [System.Drawing.Color]::FromArgb(139, 100, 0)
        "White"     = [System.Drawing.Color]::FromArgb(51, 51, 51)
        "Gray"      = [System.Drawing.Color]::FromArgb(130, 130, 130)
        "LightGray" = [System.Drawing.Color]::FromArgb(150, 150, 150)
        "DarkGray"  = [System.Drawing.Color]::FromArgb(170, 170, 170)
        "Red"       = [System.Drawing.Color]::FromArgb(176, 16, 16)
    }
    $useBold = ($color -eq "Lime") -or ($msg -match "^={3,}") -or ($msg -match "^(COMPLETED|PREVIEW READY|EXTRACTION COMPLETE|PROCESSING CANCELLED)")
    $txtLog.SelectionStart  = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    if ($colorMap.ContainsKey($color)) {
        $txtLog.SelectionColor = $colorMap[$color]
    } else {
        $txtLog.SelectionColor = [System.Drawing.Color]::FromArgb(150, 150, 150)
    }
    if ($useBold) {
        $txtLog.SelectionFont = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
    } else {
        $txtLog.SelectionFont = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)
    }
    $txtLog.AppendText("$msg`n")
    $txtLog.ScrollToCaret()
}

# ============================================================
# --- PHASE 2 BLOCK: processing pipeline (spreads + Start-ThreadJob)
# Reads parameters from $script:p2* -- called both from the direct click and
# from the PDF extraction timer completion (pendingPDF).
# ============================================================
# --- RUN MODE HELPERS (PROCESS <-> CANCEL) ---
$script:EnterRunMode = {
    $script:IsRunning       = $true
    $script:CancelRequested = $false
    $btnProcessar.Text      = "CANCEL"
    $btnProcessar.BackColor = [System.Drawing.Color]::FromArgb(180, 30, 30)
    $btnProcessar.Enabled   = $true
    $btnPasta.Enabled       = $false
    $btnSpreads.Enabled     = $false
    $btnImportPDF.Enabled   = $false
}
$script:ExitRunMode = {
    $script:IsRunning       = $false
    $script:CancelRequested = $false
    $btnProcessar.Text      = "PROCESS IMAGES"
    $btnProcessar.BackColor = [System.Drawing.Color]::FromArgb(0, 168, 225)
    $btnProcessar.Enabled   = $true
    $btnPasta.Enabled       = $true
    $p = $txtPasta.Text.TrimEnd('\')
    $btnSpreads.Enabled     = (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path $p -PathType Container))
    $btnImportPDF.Enabled   = $true
}

$script:Phase2Block = {
    $ROOT      = $script:p2ROOT
    $fuzz      = $script:p2Fuzz
    $nitidez   = $script:p2Nitidez
    $level     = $script:p2Level
    $quality   = $script:p2Quality
    $skipExist = $script:p2Skip
    $nThreads  = $script:p2Threads
    $useFlat   = $script:p2UseFlat
    $script:OUTPUT = $script:p2OUTPUT

    Write-Log "----------------------------------------------" "Gray"

    # ---- Spread processing ----
    $spreadExcludeSet   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $spreadTempFiles    = [System.Collections.Generic.List[string]]::new()
    $spreadOutMap       = @{}
    $script:spreadTempDir = ""

    if ($script:SpreadPairs.Count -gt 0) {
        $script:spreadTempDir = Join-Path $ROOT "_spreads_temp"
        if (!(Test-Path $script:spreadTempDir)) {
            try {
                New-Item -ItemType Directory -Path $script:spreadTempDir -Force -ErrorAction Stop | Out-Null
            } catch {
                Write-Log "[ERROR] Could not create temporary spreads folder: $($_.Exception.Message)" "Red"
                & $script:ExitRunMode
                return
            }
        }
        Write-Log "--- Merging $($script:SpreadPairs.Count) spread(s) ---" "Cyan"
        $sIdx = 1
        foreach ($pair in $script:SpreadPairs) {
            $pg1 = $pair.L; $pg2 = $pair.R
            $spreadExcludeSet.Add($pg1) | Out-Null
            $spreadExcludeSet.Add($pg2) | Out-Null
            $tName = "spread_{0:D3}.jpg" -f $sIdx
            $tOut  = Join-Path $script:spreadTempDir $tName
            $mergeOut = @(& magick "$pg1" "$pg2" +append -strip "$tOut" 2>&1)
            if ($LASTEXITCODE -eq 0) {
                $spreadTempFiles.Add($tOut)
                $n1 = [System.IO.Path]::GetFileName($pg1)
                $n2 = [System.IO.Path]::GetFileName($pg2)
                Write-Log "Spread $sIdx : $n1  +  $n2  ->  $tName" "White"
            } else {
                $errDetail = ($mergeOut | Where-Object { $_ } | ForEach-Object { "$_" }) -join " "
                Write-Log "[ERROR] Failed to merge spread $sIdx ($([System.IO.Path]::GetFileName($pg1)) + $([System.IO.Path]::GetFileName($pg2)))" "Red"
                if ($errDetail) { Write-Log "  Detail: $errDetail" "Red" }
                $spreadTempFiles.Add("")
            }
            $sIdx++
        }
        Write-Log "----------------------------------------------" "Gray"
    }

    $validSpreadItems = @($spreadTempFiles | Where-Object { $_ -ne "" } | ForEach-Object { Get-Item $_ })

    if (-not $useFlat -and $validSpreadItems.Count -gt 0) {
        $spreadsOutDir = Join-Path $script:OUTPUT "spreads"
        $oIdx = 1
        foreach ($si in $validSpreadItems) {
            $oName = "spread_{0:D3}.jpg" -f $oIdx
            $spreadOutMap[$si.FullName] = Join-Path $spreadsOutDir $oName
            $oIdx++
        }
    }

    $rawFiles = Get-ChildItem -Path $ROOT -Recurse -Include *.jpg, *.png |
        Where-Object {
            $_.FullName -notmatch "\\output\\" -and
            $_.FullName -notmatch "\\output_kc\\" -and
            $_.FullName -notmatch "\\_spreads_temp\\" -and
            (-not $spreadExcludeSet.Contains($_.FullName))
        }

    if ($useFlat) {
        # BUG-10 fix: sort ALL source files (including spread source pages) to determine correct positions
        $sortedAll = Get-ChildItem -Path $ROOT -Recurse -Include *.jpg, *.png |
            Where-Object {
                $_.FullName -notmatch "\\output\\" -and
                $_.FullName -notmatch "\\output_kc\\" -and
                $_.FullName -notmatch "\\_spreads_temp\\"
            } | Sort-Object {
                $rel   = $_.FullName.Substring($ROOT.Length).TrimStart('\','/')
                $dir   = Split-Path $rel -Parent
                $fname = $_.Name
                $dPad  = [regex]::Replace($dir,   '\d+', { $args[0].Value.PadLeft(10,'0') })
                $fPad  = [regex]::Replace($fname,  '\d+', { $args[0].Value.PadLeft(10,'0') })
                "$dPad\$fPad"
            }

        $spreadInsertAt  = @{}
        $spreadSkipPages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $posMap = @{}; $posIdx = 0
        foreach ($f in $sortedAll) { $posMap[$f.FullName] = $posIdx; $posIdx++ }

        $vIdx = 0
        for ($si = 0; $si -lt $spreadTempFiles.Count; $si++) {
            if ($spreadTempFiles[$si] -eq "") { continue }
            $pair = $script:SpreadPairs[$si]
            $pg1  = $pair.L; $pg2 = $pair.R
            $p1   = if ($posMap.ContainsKey($pg1)) { $posMap[$pg1] } else { [int]::MaxValue }
            $p2   = if ($posMap.ContainsKey($pg2)) { $posMap[$pg2] } else { [int]::MaxValue }
            if ($p1 -le $p2) {
                $spreadInsertAt[$pg1] = $validSpreadItems[$vIdx]
                $spreadSkipPages.Add($pg2) | Out-Null
            } else {
                $spreadInsertAt[$pg2] = $validSpreadItems[$vIdx]
                $spreadSkipPages.Add($pg1) | Out-Null
            }
            $vIdx++
        }

        $tmp = [System.Collections.Generic.List[object]]::new()
        foreach ($f in $sortedAll) {
            if     ($spreadSkipPages.Contains($f.FullName))   { continue }
            elseif ($spreadInsertAt.ContainsKey($f.FullName)) { $tmp.Add($spreadInsertAt[$f.FullName]) }
            else   { $tmp.Add($f) }
        }
        $allFiles = $tmp.ToArray()
    } else {
        $allFiles = @($rawFiles) + $validSpreadItems
    }

    $total = @($allFiles).Count

    if ($total -eq 0) {
        Write-Log "No .jpg or .png images found in the selected folder." "Yellow"
        & $script:ExitRunMode
        return
    }

    Write-Log "$total images to process (including $($validSpreadItems.Count) spread(s))." "White"

    $seqMap = @{}
    if ($useFlat) {
        $idx = 1
        foreach ($f in $allFiles) {
            $seqStr              = "{0:D4}" -f $idx
            $seqMap[$f.FullName] = Join-Path $script:OUTPUT "${seqStr}.jpg"
            $idx++
        }
    }

    $countExisting = 0
    if ($skipExist) {
        foreach ($fileItem in $allFiles) {
            if ($useFlat) {
                $out = $seqMap[$fileItem.FullName]
            } elseif ($spreadOutMap.ContainsKey($fileItem.FullName)) {
                $out = $spreadOutMap[$fileItem.FullName]
            } else {
                $fn  = [System.IO.Path]::GetFileNameWithoutExtension($fileItem.FullName)
                $rel = $fileItem.FullName.Substring($ROOT.Length).TrimStart('\', '/')
                $dir = Split-Path $rel -Parent
                if ($dir -match '^[A-Z]:') { $dir = $dir.Substring(2).TrimStart('\') }
                $tDir = if ([string]::IsNullOrWhiteSpace($dir)) { $script:OUTPUT } else { Join-Path $script:OUTPUT $dir }
                $out  = Join-Path $tDir ($fn + '_upscale.jpg')
            }
            if (Test-Path $out) { $countExisting++ }
        }
    }

    if ($skipExist -and $countExisting -gt 0) {
        Write-Log "[WARNING] Skip enabled -- $countExisting of $total file(s) already have output and will be skipped." "Yellow"
    } else {
        Write-Log "No existing files detected in the output. Processing everything." "Gray"
    }
    Write-Log "----------------------------------------------" "Gray"

    if ($skipExist -and $countExisting -gt 0) {
        $msgResp = [System.Windows.Forms.MessageBox]::Show(
            "$countExisting of $total image(s) have already been processed and will be SKIPPED.`n`nWhat do you want to do?`n`n[Yes]  Continue (skip existing)`n[No]   Reprocess everything (ignore skip)`n[Cancel]  Cancel",
            "Kindle Scribe Converter v1.24.3 - Existing files detected",
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($msgResp -eq [System.Windows.Forms.DialogResult]::Cancel) {
            Write-Log "Processing cancelled by user." "Yellow"
            & $script:ExitRunMode
            return
        }
        if ($msgResp -eq [System.Windows.Forms.DialogResult]::No) {
            $skipExist = $false
            Write-Log "[INFO] Reprocess everything -- skip disabled for this run." "Cyan"
        }
    }

    Write-Log "Starting processing..." "White"
    $script:StartTime = [DateTime]::Now

    $progressBar.Maximum = $total
    $progressBar.Value   = 0

    & $script:EnterRunMode

    # PS7: build the per-file data list before dispatching
    $fileDataList = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($fileItem in $allFiles) {
        if ($useFlat) {
            $overrideOut = $seqMap[$fileItem.FullName]
        } elseif ($spreadOutMap.ContainsKey($fileItem.FullName)) {
            $overrideOut = $spreadOutMap[$fileItem.FullName]
        } else {
            $overrideOut = ""
        }
        $fileDataList.Add(@{ Path = $fileItem.FullName; Override = $overrideOut })
    }

    $workerSrc = $script:WorkerBlock.ToString()
    $script:batchJob = Start-ThreadJob -ScriptBlock {
        param($fileData, $workerSrc, $ROOT, $OUTPUT, $fuzz, $nitidez, $level, $quality, $skipExist, $nThreads)
        $fileData | ForEach-Object -Parallel {
            $wb     = [scriptblock]::Create($using:workerSrc)
            $result = & $wb $_.Path $using:ROOT $using:OUTPUT $using:fuzz $using:nitidez $using:level $using:quality $using:skipExist $_.Override
            $result
        } -ThrottleLimit $nThreads
    } -ArgumentList $fileDataList, $workerSrc, $ROOT, $script:OUTPUT, $fuzz, $nitidez, $level, $quality, $skipExist, $nThreads

    $script:CountProcessed = 0
    $script:CountSkipped   = 0
    $script:CountErrors    = 0
    $script:TotalJobs      = $total
    $script:ProcessingDone = $false

    $script:pollTimer          = New-Object System.Windows.Forms.Timer
    $script:pollTimer.Interval = 300
    $script:pollTimer.Add_Tick({
        if ($script:CancelRequested -and -not $script:ProcessingDone) {
            $script:ProcessingDone = $true
            $script:pollTimer.Stop()
            Stop-Job  $script:batchJob -ErrorAction SilentlyContinue
            Remove-Job $script:batchJob -ErrorAction SilentlyContinue
            if ($script:spreadTempDir -ne "" -and (Test-Path $script:spreadTempDir)) {
                Remove-Item -Path $script:spreadTempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Write-Log "===============================================" "Yellow"
            Write-Log "PROCESSING CANCELLED BY USER." "Yellow"
            Write-Log "===============================================" "Yellow"
            $lblStatus.Text    = "Cancelled by user."
            $progressBar.Value = 0
            & $script:ExitRunMode
            return
        }

        $newR = @(Receive-Job -Job $script:batchJob -ErrorAction SilentlyContinue)
        foreach ($result in $newR) {
            if ($null -eq $result -or $null -eq $result.Status) { continue }
            switch ($result.Status) {
                "skipped" { $script:CountSkipped++; Write-Log "[SKIPPED] $($result.RelPath)" "DarkGray" }
                "error"   { $script:CountErrors++;  Write-Log "[ERROR] $($result.RelPath)" "Red"; Write-Log "  $($result.ErrorMsg)" "Red" }
                default   {
                    $script:CountProcessed++
                    Write-Log "[OK] $($result.RelPath)" "White"
                    Write-Log "  Orientation: $($result.Orient)" "Yellow"
                    Write-Log "  Background : $($result.Bg) (corner = $($result.MeanVal))" "Cyan"
                    Write-Log "  Saved to   : $($result.Outfile)" "Green"
                }
            }
        }

        $done = $script:CountProcessed + $script:CountSkipped + $script:CountErrors
        $progressBar.Value = [math]::Min($progressBar.Maximum, $done)
        $lblStatus.Text    = "Processed: $($script:CountProcessed) | Skipped: $($script:CountSkipped) | Errors: $($script:CountErrors) | Total: $($script:TotalJobs)"

        if ($script:batchJob.State -in @('Completed','Failed','Stopped') -and -not $script:ProcessingDone) {
            $script:ProcessingDone = $true
            $script:pollTimer.Stop()
            # Drain remaining results
            $tail = @(Receive-Job -Job $script:batchJob -ErrorAction SilentlyContinue)
            foreach ($result in $tail) {
                if ($null -eq $result -or $null -eq $result.Status) { continue }
                switch ($result.Status) {
                    "skipped" { $script:CountSkipped++; Write-Log "[SKIPPED] $($result.RelPath)" "DarkGray" }
                    "error"   { $script:CountErrors++;  Write-Log "[ERROR] $($result.RelPath)" "Red"; Write-Log "  $($result.ErrorMsg)" "Red" }
                    default   {
                        $script:CountProcessed++
                        Write-Log "[OK] $($result.RelPath)" "White"
                        Write-Log "  Orientation: $($result.Orient)" "Yellow"
                        Write-Log "  Background : $($result.Bg) (corner = $($result.MeanVal))" "Cyan"
                        Write-Log "  Saved to   : $($result.Outfile)" "Green"
                    }
                }
            }
            Remove-Job $script:batchJob -ErrorAction SilentlyContinue
            $progressBar.Value = $progressBar.Maximum
            $script:Elapsed    = [DateTime]::Now - $script:StartTime
            $elapsedStr        = "{0:hh\:mm\:ss}" -f $script:Elapsed
            $lblStatus.Text    = "Done! Processed: $($script:CountProcessed) | Skipped: $($script:CountSkipped) | Errors: $($script:CountErrors) | Time: $elapsedStr"
            Write-Log "===============================================" "Cyan"
            Write-Log "COMPLETED: $($script:CountProcessed) processed | $($script:CountSkipped) skipped | $($script:CountErrors) errors | Time: $elapsedStr" "Lime"
            Write-Log "Output: $script:OUTPUT" "Gray"
            Write-Log "===============================================" "Cyan"

            if ($script:spreadTempDir -ne "" -and (Test-Path $script:spreadTempDir)) {
                Remove-Item -Path $script:spreadTempDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Temp spreads removed." "DarkGray"
            }

            & $script:ExitRunMode

            [System.Windows.Forms.MessageBox]::Show(
                "Processing complete!`n`nProcessed : $($script:CountProcessed)`nSkipped   : $($script:CountSkipped)`nErrors    : $($script:CountErrors)`nTime      : $elapsedStr`n`nOutput: $script:OUTPUT",
                "Kindle Scribe Converter v1.24.3",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        }
    })
    $script:pollTimer.Start()
}

# ============================================================
# --- LOGIC: PROCESS IMAGES ---
# ============================================================
$btnProcessar.Add_Click({
    if ($script:IsRunning) {
        $script:CancelRequested = $true
        $btnProcessar.Enabled   = $false
        $btnProcessar.Text      = "Cancelling..."
        return
    }
    $ROOT = $txtPasta.Text.TrimEnd("\")
    if ([string]::IsNullOrWhiteSpace($ROOT) -or !(Test-Path $ROOT)) {
        [System.Windows.Forms.MessageBox]::Show("Select a valid folder before processing.", "Invalid folder",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $fuzz      = $txtFuzz.Text.Trim()
    $nitidez   = ($txtNitidez.Text.Trim() -replace '[^0-9.]','')
    $level     = $txtLevel.Text.Trim()
    $quality   = $txtQuality.Text.Trim()
    $skipExist = $chkSkip.Checked
    $nThreads  = [int]$numThreads.Value

    foreach ($param in @($fuzz, $nitidez, $level, $quality)) {
        if ([string]::IsNullOrWhiteSpace($param)) {
            [System.Windows.Forms.MessageBox]::Show("All parameters must be filled in.", "Empty parameter",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
    }

    $escolha = Show-OrganizacaoPopup $form
    if ($escolha -eq "cancel") { return }
    $useFlat = ($escolha -eq "flat")

    if ($useFlat) {
        $script:OUTPUT = Join-Path $ROOT "output_kc"
    } else {
        $script:OUTPUT = Join-Path $ROOT "output"
    }
    if (!(Test-Path $script:OUTPUT)) { New-Item -ItemType Directory -Path $script:OUTPUT | Out-Null }

    $txtLog.Clear()
    Write-Log "=== Kindle Scribe Converter v1.24.3 ===" "Cyan"
    Write-Log "Folder  : $ROOT" "Gray"
    $modoLabel = if ($useFlat) { "Kindle Create (flat, output_kc\)" } else { "With chapters (subfolders, output\)" }
    Write-Log "Mode    : $modoLabel" "Cyan"
    Write-Log "Threads : $nThreads (of $([Environment]::ProcessorCount) logical cores)" "Cyan"
    Write-Log "Params  : Resize=2480x1860/1860x2480 | Gray | Fuzz=$fuzz (reserved) | Sharpness=0x0.6+$nitidez+0.02 | Level=$level | Quality=$quality | Contrast=0.5%x0.5% (fixed)" "Gray"

    # Save params for Phase2Block (read both in the direct flow and after PDF extraction)
    $script:p2ROOT    = $ROOT
    $script:p2Fuzz    = $fuzz
    $script:p2Nitidez = $nitidez
    $script:p2Level   = $level
    $script:p2Quality = $quality
    $script:p2Skip    = $skipExist
    $script:p2Threads = $nThreads
    $script:p2UseFlat = $useFlat
    $script:p2OUTPUT  = $script:OUTPUT

    # -------------------------------------------------------
    # PHASE 1: if there is a pending PDF, extract at real DPI first
    # -------------------------------------------------------
    if ($script:pendingPDF -ne $null) {
        $pdfPathP  = $script:pendingPDF.Path
        $script:pdf2FileName = [System.IO.Path]::GetFileName($pdfPathP)
        $dpiP      = $script:pendingPDF.DPI
        $outDirP   = $script:pendingPDF.OutputDir
        $prevDirP  = $script:pendingPDF.PreviewDir

        # Count pages
        $lblStatus.Text = "Counting pages: $($script:pdf2FileName)..."
        $form.Refresh()
        $identLinesP = @(& magick identify -ping "$pdfPathP" 2>$null)
        $pageCountP  = $identLinesP.Count
        if ($pageCountP -le 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not count the PDF pages.`n`nCheck that the file still exists and that Ghostscript is installed.",
                "Error reading PDF",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }

        # Ensure outputDir exists
        if (!(Test-Path $outDirP)) { New-Item -ItemType Directory -Path $outDirP | Out-Null }

        Write-Log "--- Phase 1: Extracting PDF at $dpiP DPI ($pageCountP pages) ---" "Cyan"

        $progressBar.Maximum = $pageCountP
        $progressBar.Value   = 0
        $lblStatus.Text      = "Phase 1: $($script:pdf2FileName) -- $dpiP DPI..."

        & $script:EnterRunMode

        # PS7: Start-ThreadJob + ForEach-Object -Parallel for Phase 1 extraction
        $pdf2WorkerSrc = $script:PDFWorkerBlock.ToString()
        $pdf2Indices   = 0..($pageCountP - 1)
        $script:pdf2BatchJob = Start-ThreadJob -ScriptBlock {
            param($indices, $workerSrc, $pdfPath, $outDir, $dpi, $nThreads)
            $indices | ForEach-Object -Parallel {
                $wb     = [scriptblock]::Create($using:workerSrc)
                $result = & $wb $using:pdfPath $using:outDir $_ $using:dpi
                $result
            } -ThrottleLimit $nThreads
        } -ArgumentList $pdf2Indices, $pdf2WorkerSrc, $pdfPathP, $outDirP, $dpiP, $nThreads

        $script:pdf2OK    = 0
        $script:pdf2Err   = 0
        $script:pdf2Total = $pageCountP
        $script:pdf2Done  = $false
        $script:pdf2PrevDir = $prevDirP
        $script:pdf2OutDir  = $outDirP

        $script:pdf2Timer          = New-Object System.Windows.Forms.Timer
        $script:pdf2Timer.Interval = 300
        $script:pdf2Timer.Add_Tick({
            if ($script:CancelRequested -and -not $script:pdf2Done) {
                $script:pdf2Done = $true
                $script:pdf2Timer.Stop()
                Stop-Job  $script:pdf2BatchJob -ErrorAction SilentlyContinue
                Remove-Job $script:pdf2BatchJob -ErrorAction SilentlyContinue
                Write-Log "Phase 1 cancelled by user." "Yellow"
                $lblStatus.Text    = "Cancelled."
                $progressBar.Value = 0
                & $script:ExitRunMode
                return
            }

            $newR2 = @(Receive-Job -Job $script:pdf2BatchJob -ErrorAction SilentlyContinue)
            foreach ($r in $newR2) {
                if ($null -eq $r -or $null -eq $r.Status) { continue }
                if ($r.Status -eq "error") {
                    $script:pdf2Err++
                    Write-Log "[ERROR Phase1] Page $($r.Page): $($r.ErrorMsg)" "Red"
                } else {
                    $script:pdf2OK++
                    Write-Log "[Phase1] Page $($r.Page) -> $([System.IO.Path]::GetFileName($r.OutFile))" "Gray"
                }
            }

            $done2 = $script:pdf2OK + $script:pdf2Err
            $progressBar.Value = [math]::Min($progressBar.Maximum, $done2)
            $lblStatus.Text    = "$($script:pdf2FileName) -- $done2 / $($script:pdf2Total) | Errors: $($script:pdf2Err)"

            if ($script:pdf2BatchJob.State -in @('Completed','Failed','Stopped') -and -not $script:pdf2Done) {
                $script:pdf2Done = $true
                $script:pdf2Timer.Stop()
                # Drain remaining results
                $tail2 = @(Receive-Job -Job $script:pdf2BatchJob -ErrorAction SilentlyContinue)
                foreach ($r in $tail2) {
                    if ($null -eq $r -or $null -eq $r.Status) { continue }
                    if ($r.Status -eq "error") {
                        $script:pdf2Err++
                        Write-Log "[ERROR Phase1] Page $($r.Page): $($r.ErrorMsg)" "Red"
                    } else {
                        $script:pdf2OK++
                        Write-Log "[Phase1] Page $($r.Page) -> $([System.IO.Path]::GetFileName($r.OutFile))" "Gray"
                    }
                }
                Remove-Job $script:pdf2BatchJob -ErrorAction SilentlyContinue

                Write-Log "--- Phase 1 complete: $($script:pdf2OK) pages | $($script:pdf2Err) errors ---" "Lime"

                # Remap SpreadPairs: replace the previewDir path with the final outDir
                $prevDir = $script:pdf2PrevDir
                $outDir  = $script:pdf2OutDir
                foreach ($pair in $script:SpreadPairs) {
                    $pair.L = Join-Path $outDir ([System.IO.Path]::GetFileName($pair.L))
                    $pair.R = Join-Path $outDir ([System.IO.Path]::GetFileName($pair.R))
                }
                Write-Log "SpreadPairs remapped to final outputDir." "Cyan"

                # Clean up temp previewDir
                if (Test-Path $prevDir) {
                    Remove-Item -Path $prevDir -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Temp preview removed." "DarkGray"
                }

                # Clear pendingPDF state
                $script:pendingPDF = $null

                Write-Log "--- Phase 2: Starting image processing ---" "Cyan"
                & $script:Phase2Block
            }
        })
        $script:pdf2Timer.Start()
        return  # wait for the timer to trigger Phase2Block
    }

    # -------------------------------------------------------
    # Direct flow (no pendingPDF): go straight to Phase 2
    # -------------------------------------------------------
    & $script:Phase2Block
})
# ============================================================
# --- HORIZONTAL PANEL CENTERING ---
# ============================================================
$centerPanel = {
    # --- Adaptive adjustment to screen height (fix BUG-20: monitors < 860px) ---
    $workArea   = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $titleExtra = $form.Height - $form.ClientSize.Height
    $maxClientH = $workArea.Height - $titleExtra
    if ($form.ClientSize.Height -gt $maxClientH) {
        $form.ClientSize = New-Object System.Drawing.Size($form.ClientSize.Width, $maxClientH)
        $contentPanel.AutoScroll = $true
    }

    # --- Horizontal centering ---
    $fw = $form.ClientSize.Width
    $fh = $form.ClientSize.Height
    $pw = [Math]::Min($fw, $panelMaxW)
    $px = [Math]::Max(0, [int](($fw - $pw) / 2))
    $contentPanel.Left   = $px
    $contentPanel.Width  = $pw
    $contentPanel.Height = $fh - 70
    $headerPanel.Left    = $px
    $headerPanel.Width   = $pw
}

$form.Add_Load(        $centerPanel )
$form.Add_SizeChanged( $centerPanel )

[System.Windows.Forms.Application]::Run($form)
