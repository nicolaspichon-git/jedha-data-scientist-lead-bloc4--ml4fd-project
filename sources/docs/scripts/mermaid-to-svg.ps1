<#
.SYNOPSIS
    Converts a list of Mermaid diagrams (.md) into SVG images using mmdc (Mermaid CLI).

.DESCRIPTION
    This script loads a list of (file path, width) pairs from a text file passed as a
    parameter, then iterates over that list to convert each Mermaid file into an SVG
    using the following command template:
        mmdc -i '<path>' -o '.\<basename>.svg' [-c '.\mermaid-config.json'] [--width <width>]

    The --width option is only passed to mmdc when a width is explicitly defined on the
    corresponding line of the text file. If no width is given, mmdc is called without
    --width and falls back to its own default sizing.

    If a local "mermaid-config.json" file exists in the current directory, it is passed
    to mmdc via the -c option for every conversion. If it does not exist, the -c option
    is omitted entirely.

    Since the input files are Markdown (.md) files containing a ```mermaid code block
    (so they still preview correctly in VS Code / Obsidian), mmdc automatically numbers
    the diagram it extracts (e.g. "basename-1.svg"). This script renames that file back
    to "basename.svg" after each conversion.

.PARAMETER ListFile
    Path to a text file containing one entry per line, formatted as:
        <file path>,<width>
    The width is optional: if omitted (no comma, or an empty value after the comma),
    mmdc is called without --width. Blank lines and lines starting with '#' are ignored.

    Example file content:
        C:\diagrams\architecture.md,1200
        C:\diagrams\sequence.md,800
        C:\diagrams\overview.md
        .\user-flow.md,

.OUTPUTS
    The path of each SVG successfully produced, so the script can be piped into
    add-logos-to-svg.ps1. Progress messages go to the host, not the pipeline.

.EXAMPLE
    .\mermaid-to-svg.ps1 -ListFile ".\diagrams-list.txt"

.EXAMPLE
    .\mermaid-to-svg.ps1 -ListFile ".\diagrams-list.txt" |
        ..\..\scripts\add-logos-to-svg.ps1

.PREREQUISITES
    - Node.js installed
    - Mermaid CLI installed globally: npm install -g @mermaid-js/mermaid-cli
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ListFile
)

# --- Align the .NET current directory with the PowerShell location ---
# Native commands and .NET APIs resolve relative paths against
# Environment.CurrentDirectory, which does not follow Set-Location. mmdc is a
# child process and writes its output relative to that directory.
[Environment]::CurrentDirectory = $PWD.Path

# --- Check that the list file exists ---
if (-not (Test-Path -LiteralPath $ListFile)) {
    Write-Error "List file not found: $ListFile"
    exit 1
}

# --- Load the list of (file path, width) pairs from the text file ---
$diagrams = @()

Get-Content -LiteralPath $ListFile | ForEach-Object {
    $line = $_.Trim()

    # Skip blank lines and comments
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
        return
    }

    $parts = $line -split ','

    if ($parts.Count -gt 2) {
        Write-Warning "Malformed line, skipped: '$line'"
        return
    }

    $path      = $parts[0].Trim()
    $widthText = if ($parts.Count -eq 2) { $parts[1].Trim() } else { '' }

    if ([string]::IsNullOrWhiteSpace($widthText)) {
        # No width specified on this line: mmdc will be called without --width
        $width = $null
    }
    elseif ($widthText -as [int]) {
        $width = [int]$widthText
    }
    else {
        Write-Warning "Invalid width, skipped: '$line'"
        return
    }

    $diagrams += [PSCustomObject]@{
        Path  = $path
        Width = $width
    }
}

if ($diagrams.Count -eq 0) {
    Write-Warning "No valid entries found in '$ListFile'. Nothing to convert."
    exit 0
}

# --- Check for a local Mermaid configuration file ---
$configPath = Join-Path $PSScriptRoot "mermaid-config.json"
$hasConfig  = Test-Path -LiteralPath $configPath

if ($hasConfig) {
    Write-Host "Using local configuration file: $configPath" -ForegroundColor DarkCyan
} else {
    Write-Host "No local '$configPath' found; converting without -c option." -ForegroundColor DarkCyan
}

# --- Iterate over the list and convert each file ---
foreach ($diagram in $diagrams) {

    $path  = $diagram.Path
    $width = $diagram.Width

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Warning "File not found, skipped: $path"
        continue
    }

    $basename   = [System.IO.Path]::GetFileNameWithoutExtension($path)
    $outputPath = ".\$basename.svg"

    # When the input is a .md file, mmdc treats it as Markdown and numbers each
    # diagram it finds (e.g. "basename-1.svg"), even if there is only one. This
    # is the name mmdc will actually produce for the first diagram in the file.
    $numberedOutputPath = ".\$basename-1.svg"

    # Build the mmdc argument list; -c and --width are only added when applicable
    $mmdcArgs = @('-i', $path, '-o', $outputPath)
    if ($hasConfig) {
        $mmdcArgs += @('-c', $configPath)
    }
    if ($null -ne $width) {
        $mmdcArgs += @('--width', $width)
    }

    $widthLabel = if ($null -ne $width) { "$width px" } else { "mmdc default" }
    Write-Host "Converting '$path' -> '$outputPath' (width: $widthLabel)" -ForegroundColor Cyan

    try {
        # mmdc writes its own progress lines to stdout. In PowerShell a native
        # command's stdout flows straight into the script's output stream, so it
        # would pollute the pipeline. Capture it and surface it only on failure.
        $mmdcOutput = & mmdc @mmdcArgs 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0) {
            if (Test-Path -LiteralPath $numberedOutputPath) {
                # Strip the "-1" suffix added by mmdc so the file matches $outputPath
                Move-Item -LiteralPath $numberedOutputPath -Destination $outputPath -Force

                if (Test-Path -LiteralPath ".\$basename-2.svg") {
                    Write-Warning "  -> Multiple diagrams found in '$path'; only the first one was kept as '$outputPath'"
                }
            }
            Write-Host "  -> OK" -ForegroundColor Green

            # Emit the produced path so the script can be piped, e.g.
            #   .\mermaid-to-svg.ps1 -ListFile .\diagrams-list.txt |
            #       ..\..\scripts\add-logos-to-svg.ps1
            Write-Output $outputPath
        } else {
            Write-Warning "  -> mmdc returned an error code ($LASTEXITCODE) for '$path'"
            if ($mmdcOutput) { Write-Host $mmdcOutput -ForegroundColor DarkYellow }
        }
    }
    catch {
        Write-Error "  -> Conversion failed for '$path': $_"
    }
}

Write-Host "`nConversion complete." -ForegroundColor Yellow