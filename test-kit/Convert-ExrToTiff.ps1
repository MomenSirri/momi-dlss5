<#
.SYNOPSIS
    Converts EXR beauty passes to 16-bit sRGB TIFFs for DLSS 5 community-tool tests,
    plus browser-friendly review copies for the blind A/B page (ab-review.html).

.DESCRIPTION
    Stills:    every .exr becomes  for-tool\<name>.tif     (16-bit sRGB TIFF, input for the tool)
                                    for-review\<name>.png  (16-bit PNG, "Originals" for the A/B page)
    Sequence:  a folder of frames becomes
                                    for-tool\<shot>_frames\<frame>.tif  (16-bit TIFF per frame)
                                    for-tool\<shot>.mp4                 (H.264, input for the tool's video mode)
                                    for-review\<shot>.mp4               (same movie, "Originals" for the A/B page)

    The beauty is read as scene-linear, optionally exposed and tone mapped, encoded with the
    sRGB curve and, if given, passed through a display .cube LUT. Values above 1.0 clip unless
    -ToneMap is used. Every conversion is appended to conversion-log.csv in the output folder.

    Needs ffmpeg (a "full" build with zscale and libx264, e.g. C:\ffmpeg\bin\ffmpeg.exe).
    Works in Windows PowerShell 5.1 and PowerShell 7.

.PARAMETER InputPath
    One or more .exr files or folders. A folder is treated as a set of stills unless -Sequence is set.
.PARAMETER OutputDir
    Where to write results. Default: a "dlss5-test" folder next to the first input
    (inside it, for a folder of stills; beside it, for a sequence folder).
.PARAMETER Sequence
    Treat each input folder as one animation: frames sorted by name, one movie per folder.
.PARAMETER Exposure
    Exposure change in stops, applied in linear light before the sRGB curve. Use a dot: 0.5, -1.
.PARAMETER ToneMap
    none (default): values above 1.0 clip, like a plain sRGB view.
    rolloff: keeps shadows and midtones, compresses highlights up to -WhitePoint. Best first try.
    reinhard: softer curve overall. hable: filmic curve with darker midtones (raise -Exposure).
.PARAMETER WhitePoint
    Scene-linear value that becomes pure white when -ToneMap is not none. Default 8 (3 stops over 1.0).
.PARAMETER Lut
    Optional .cube LUT applied after the sRGB curve (a display-referred "look" LUT).
.PARAMETER Layer
    EXR layer that holds the beauty, for files where it is not the main RGB channels.
    Without it the script uses the main RGB channels, or a single layer named like Beauty/RGBA.
.PARAMETER Part
    Part number for multi-part EXR files. Default 0.
.PARAMETER Fps
    Frame rate for sequence movies. Default 25.
.PARAMETER Crf
    H.264 quality for sequence movies (lower is better, 0-51). Default 12, visually lossless.
.PARAMETER KeepAlpha
    Write RGBA TIFFs instead of RGB. Review copies are always RGB.
.PARAMETER ListLayers
    Only print the channels and layers in each EXR, then stop.
.PARAMETER FfmpegPath
    Full path to ffmpeg.exe if it is not on PATH or in C:\ffmpeg\bin.

.EXAMPLE
    .\Convert-ExrToTiff.ps1 D:\tests\ext_day.exr
.EXAMPLE
    .\Convert-ExrToTiff.ps1 D:\tests\stills -Exposure 0.5 -ToneMap rolloff
.EXAMPLE
    .\Convert-ExrToTiff.ps1 D:\tests\shot010 -Sequence -Fps 30
.EXAMPLE
    .\Convert-ExrToTiff.ps1 D:\tests\ext_day.exr -ListLayers
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $InputPath,
    [string] $OutputDir,
    [switch] $Sequence,
    [double] $Exposure = 0,
    [ValidateSet('none', 'rolloff', 'reinhard', 'hable')]
    [string] $ToneMap = 'none',
    [ValidateRange(1.0, 1000.0)]
    [double] $WhitePoint = 8,
    [string] $Lut,
    [string] $Layer,
    [ValidateRange(0, 1000)]
    [int] $Part = 0,
    [ValidateRange(1, 240)]
    [double] $Fps = 25,
    [ValidateRange(0, 51)]
    [int] $Crf = 12,
    [switch] $KeepAlpha,
    [switch] $ListLayers,
    [string] $FfmpegPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Invariant = [System.Globalization.CultureInfo]::InvariantCulture
$CompressionNames = @('none', 'rle', 'zips', 'zip', 'piz', 'pxr24', 'b44', 'b44a', 'dwaa', 'dwab')
$BeautyLayerNames = @('beauty', 'rgba', 'rgb', 'combined', 'composite', 'main', 'default')

# ---------------------------------------------------------------- helpers

function Format-NativeArg([string] $Value) {
    # Quote one argument the way CommandLineToArgvW expects, so paths with spaces survive in PS 5.1 and 7.
    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $sb = New-Object System.Text.StringBuilder
    [void] $sb.Append('"')
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') { $slashes++; continue }
        if ($ch -eq '"') {
            [void] $sb.Append('\' * ($slashes * 2 + 1)).Append('"')
        } else {
            if ($slashes -gt 0) { [void] $sb.Append('\' * $slashes) }
            [void] $sb.Append($ch)
        }
        $slashes = 0
    }
    if ($slashes -gt 0) { [void] $sb.Append('\' * ($slashes * 2)) }
    [void] $sb.Append('"')
    return $sb.ToString()
}

function Invoke-Native([string] $Exe, [string[]] $ArgList) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (($ArgList | ForEach-Object { Format-NativeArg $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return [pscustomobject]@{ ExitCode = $proc.ExitCode; StdOut = $stdout.Result; StdErr = $stderr.Trim() }
}

function Find-Ffmpeg {
    if ($FfmpegPath) {
        if (-not (Test-Path -LiteralPath $FfmpegPath -PathType Leaf)) { throw "ffmpeg not found at '$FfmpegPath'." }
        return (Resolve-Path -LiteralPath $FfmpegPath).ProviderPath
    }
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @('C:\ffmpeg\bin\ffmpeg.exe', (Join-Path $PSScriptRoot 'ffmpeg.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw "ffmpeg was not found. Put ffmpeg.exe on PATH, in C:\ffmpeg\bin, or pass -FfmpegPath."
}

function Format-Number([double] $Value) {
    return $Value.ToString('0.######', $Invariant)
}

function ConvertTo-FilterPath([string] $Path) {
    # For a filter option inside single quotes: forward slashes, escaped drive colon.
    return $Path.Replace('\', '/').Replace(':', '\:')
}

function Read-CString([System.IO.BinaryReader] $Reader) {
    $bytes = New-Object System.Collections.Generic.List[byte]
    while ($true) {
        $b = $Reader.ReadByte()
        if ($b -eq 0) { break }
        $bytes.Add($b)
        if ($bytes.Count -gt 1024) { throw 'corrupt header (attribute name too long)' }
    }
    return [System.Text.Encoding]::UTF8.GetString($bytes.ToArray())
}

function Get-ExrInfo([string] $Path) {
    # Reads the first header of an OpenEXR file: channel names, compression, size, part/deep flags.
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.BinaryReader($stream)
        if ($reader.ReadInt32() -ne 20000630) { throw 'not an OpenEXR file' }
        $version = $reader.ReadInt32()
        $info = [ordered]@{
            Channels    = @()
            Compression = 'unknown'
            Width       = 0
            Height      = 0
            MultiPart   = (($version -band 0x1000) -ne 0)
            Deep        = (($version -band 0x800) -ne 0)
        }
        while ($true) {
            $name = Read-CString $reader
            if ($name -eq '') { break }
            [void] (Read-CString $reader)
            $size = $reader.ReadInt32()
            $data = $reader.ReadBytes($size)
            if ($name -eq 'channels') {
                $names = @()
                $i = 0
                while ($i -lt $data.Length -and $data[$i] -ne 0) {
                    $end = [Array]::IndexOf($data, [byte] 0, $i)
                    $names += [System.Text.Encoding]::UTF8.GetString($data, $i, $end - $i)
                    $i = $end + 1 + 16
                }
                $info.Channels = $names
            } elseif ($name -eq 'compression' -and $data.Length -ge 1) {
                $c = [int] $data[0]
                if ($c -lt $CompressionNames.Count) { $info.Compression = $CompressionNames[$c] } else { $info.Compression = "type $c" }
            } elseif ($name -eq 'dataWindow' -and $data.Length -ge 16) {
                $info.Width = [BitConverter]::ToInt32($data, 8) - [BitConverter]::ToInt32($data, 0) + 1
                $info.Height = [BitConverter]::ToInt32($data, 12) - [BitConverter]::ToInt32($data, 4) + 1
            }
        }
        return [pscustomobject] $info
    } finally {
        $stream.Dispose()
    }
}

function Get-RgbLayers($Info) {
    # Layer names ('' = main channels) that carry R, G and B.
    $byLayer = @{}
    foreach ($ch in $Info.Channels) {
        $dot = $ch.LastIndexOf('.')
        if ($dot -lt 0) { $layerName = ''; $suffix = $ch } else { $layerName = $ch.Substring(0, $dot); $suffix = $ch.Substring($dot + 1) }
        if (-not $byLayer.ContainsKey($layerName)) { $byLayer[$layerName] = @() }
        $byLayer[$layerName] += $suffix.ToUpperInvariant()
    }
    $result = @()
    foreach ($key in ($byLayer.Keys | Sort-Object)) {
        $s = $byLayer[$key]
        if (($s -contains 'R') -and ($s -contains 'G') -and ($s -contains 'B')) { $result += $key }
    }
    return , $result
}

function Resolve-BeautyLayer($Info, [string] $FileName) {
    if ($Info.Deep) { throw 'deep EXR files are not supported' }
    if ($Info.MultiPart) {
        # Only the first part's header is read here; trust -Layer/-Part and let ffmpeg decide.
        if ($Layer) { return $Layer }
        return ''
    }
    $rgbLayers = Get-RgbLayers $Info
    if ($Layer) {
        if ($rgbLayers -notcontains $Layer) {
            throw "layer '$Layer' has no R/G/B channels. Layers with RGB: $(Format-LayerList $rgbLayers)"
        }
        return $Layer
    }
    if ($rgbLayers -contains '') { return '' }
    $named = @($rgbLayers | Where-Object { $BeautyLayerNames -contains $_.ToLowerInvariant() })
    if ($named.Count -eq 1) { return $named[0] }
    if ($rgbLayers.Count -eq 1) { return $rgbLayers[0] }
    throw "no main RGB channels. Pick one with -Layer. Layers with RGB: $(Format-LayerList $rgbLayers)"
}

function Format-LayerList($Layers) {
    if ($null -eq $Layers -or @($Layers).Count -eq 0) { return '(none)' }
    return (($Layers | ForEach-Object { if ($_ -eq '') { '(main RGB)' } else { $_ } }) -join ', ')
}

function Get-FilterChain([bool] $HasZscale) {
    $parts = @()
    if ($Exposure -ne 0) { $parts += "exposure=exposure=$(Format-Number $Exposure):black=0" }
    if ($ToneMap -ne 'none') {
        # tonemap only takes float RGB without alpha. zscale drops the alpha here, because a plain
        # format conversion would clamp values above 1.0 before the curve sees them.
        $parts += 'zscale=tin=linear:t=linear:pin=709:p=709'
        $parts += 'format=gbrpf32le'
        if ($ToneMap -eq 'rolloff') { $curve = 'mobius:param=0.3' } else { $curve = $ToneMap }
        $parts += "tonemap=tonemap=$($curve):peak=$(Format-Number $WhitePoint):desat=0"
    }
    if ($HasZscale) { $parts += 'zscale=tin=linear:t=iec61966-2-1:pin=709:p=709' }
    if ($script:LutFilterPath) { $parts += "lut3d=file='$($script:LutFilterPath)'" }
    $parts += 'format=gbrp16le|gbrap16le'
    if ($KeepAlpha) { $parts += 'format=rgba64le' } else { $parts += 'format=rgb48le' }
    return ($parts -join ',')
}

function Convert-ExrFile([string] $Source, [string] $TiffPath) {
    $info = Get-ExrInfo $Source
    $beauty = Resolve-BeautyLayer $info (Split-Path -Leaf $Source)
    $ffArgs = @('-hide_banner', '-loglevel', 'error', '-y')
    if ($beauty -ne '') { $ffArgs += @('-layer', $beauty) }
    if ($Part -gt 0) { $ffArgs += @('-part', "$Part") }
    if (-not $script:HasZscale) { $ffArgs += @('-apply_trc', 'iec61966_2_1') }
    $ffArgs += @('-i', $Source, '-vf', $script:FilterChain, '-frames:v', '1', '-compression_algo', 'deflate', $TiffPath)
    $run = Invoke-Native $script:Ffmpeg $ffArgs
    if ($run.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $TiffPath)) {
        $msg = $run.StdErr
        if (-not $msg) { $msg = "ffmpeg exit code $($run.ExitCode)" }
        throw $msg
    }
    if ($beauty -eq '') { $layerLabel = '(main RGB)' } else { $layerLabel = $beauty }
    return [pscustomobject]@{ Layer = $layerLabel; Width = $info.Width; Height = $info.Height; Compression = $info.Compression }
}

function Write-ReviewPng([string] $TiffPath, [string] $PngPath) {
    $run = Invoke-Native $script:Ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-i', $TiffPath, '-frames:v', '1', '-pix_fmt', 'rgb48be', $PngPath)
    if ($run.ExitCode -ne 0) { throw "review PNG failed: $($run.StdErr)" }
}

function Write-Movie([string[]] $Frames, [string] $MoviePath) {
    $listPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "dlss5kit_$([guid]::NewGuid().ToString('N')).ffconcat")
    $duration = Format-Number (1.0 / $Fps)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('ffconcat version 1.0')
    foreach ($f in $Frames) {
        $lines.Add("file '$($f.Replace('\', '/').Replace("'", "'\''"))'")
        $lines.Add("duration $duration")
    }
    # The concat demuxer drops the last duration unless the last file is listed again.
    $lines.Add("file '$($Frames[-1].Replace('\', '/').Replace("'", "'\''"))'")
    [System.IO.File]::WriteAllLines($listPath, $lines, (New-Object System.Text.UTF8Encoding($false)))
    try {
        $ffArgs = @('-hide_banner', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', $listPath,
            '-frames:v', "$($Frames.Count)",
            '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2,scale=out_color_matrix=bt709:out_range=tv,format=yuv420p',
            '-r', (Format-Number $Fps), '-c:v', 'libx264', '-preset', 'slow', '-crf', "$Crf",
            '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709',
            '-movflags', '+faststart', $MoviePath)
        $run = Invoke-Native $script:Ffmpeg $ffArgs
        if ($run.ExitCode -ne 0) { throw "movie failed: $($run.StdErr)" }
    } finally {
        Remove-Item -LiteralPath $listPath -ErrorAction SilentlyContinue
    }
}

function Add-LogRow([string] $Source, [string] $Output, [string] $Kind, $Meta, [string] $Status, [string] $Message) {
    $row = [pscustomobject]@{
        Time        = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $Invariant)
        Kind        = $Kind
        Source      = $Source
        Output      = $Output
        Layer       = $(if ($Meta) { $Meta.Layer } else { '' })
        Width       = $(if ($Meta) { $Meta.Width } else { '' })
        Height      = $(if ($Meta) { $Meta.Height } else { '' })
        Compression = $(if ($Meta) { $Meta.Compression } else { '' })
        Exposure    = (Format-Number $Exposure)
        ToneMap     = $(if ($ToneMap -eq 'none') { 'none' } else { "$ToneMap, white $(Format-Number $WhitePoint)" })
        Lut         = $(if ($Lut) { $Lut } else { '' })
        Status      = $Status
        Message     = $Message
    }
    $row | Export-Csv -LiteralPath $script:LogPath -Append -NoTypeInformation -Encoding UTF8
}

function Get-ExrFiles([string] $Folder) {
    return @(Get-ChildItem -LiteralPath $Folder -File | Where-Object { $_.Extension -ieq '.exr' } | Sort-Object Name)
}

# ---------------------------------------------------------------- inputs

$inputs = @()
foreach ($p in $InputPath) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Input not found: $p" }
    $item = Get-Item -LiteralPath $p
    if ($item.PSIsContainer) {
        $inputs += [pscustomobject]@{ Kind = 'folder'; Item = $item }
    } elseif ($item.Extension -ieq '.exr') {
        if ($Sequence) { throw "-Sequence needs a folder of frames, not a file: $p" }
        $inputs += [pscustomobject]@{ Kind = 'file'; Item = $item }
    } else {
        throw "Not an .exr file or a folder: $p"
    }
}

if ($ListLayers) {
    foreach ($in in $inputs) {
        if ($in.Kind -eq 'file') { $files = @($in.Item) } else { $files = Get-ExrFiles $in.Item.FullName }
        foreach ($f in $files) {
            try {
                $info = Get-ExrInfo $f.FullName
                Write-Host ''
                Write-Host $f.FullName -ForegroundColor Cyan
                Write-Host ("  {0} x {1}, compression {2}{3}{4}" -f $info.Width, $info.Height, $info.Compression,
                    $(if ($info.MultiPart) { ', multi-part (first part shown; use -Part N)' } else { '' }),
                    $(if ($info.Deep) { ', DEEP (not supported)' } else { '' }))
                Write-Host "  Layers with RGB: $(Format-LayerList (Get-RgbLayers $info))"
                Write-Host "  All channels:    $($info.Channels -join ', ')"
            } catch {
                Write-Host "$($f.FullName): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    return
}

# ---------------------------------------------------------------- setup

$script:Ffmpeg = Find-Ffmpeg
$filters = (Invoke-Native $script:Ffmpeg @('-hide_banner', '-filters')).StdOut
$script:HasZscale = $filters -match '\szscale\s'
if (-not $script:HasZscale) {
    if ($Exposure -ne 0 -or $ToneMap -ne 'none') {
        throw "This ffmpeg build has no zscale filter, which -Exposure and -ToneMap need. Use a full build (for example from gyan.dev)."
    }
    Write-Warning 'ffmpeg has no zscale filter; using the decoder''s sRGB curve instead (tiny rounding differences).'
}

$script:LutFilterPath = $null
if ($Lut) {
    if (-not (Test-Path -LiteralPath $Lut -PathType Leaf)) { throw "LUT not found: $Lut" }
    $lutFull = (Resolve-Path -LiteralPath $Lut).ProviderPath
    if ($lutFull.Contains("'")) {
        $tmpLut = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'dlss5kit_look.cube')
        Copy-Item -LiteralPath $lutFull -Destination $tmpLut -Force
        $lutFull = $tmpLut
    }
    $script:LutFilterPath = ConvertTo-FilterPath $lutFull
}
$script:FilterChain = Get-FilterChain $script:HasZscale

if (-not $OutputDir) {
    $first = $inputs[0]
    if ($first.Kind -eq 'file') { $base = $first.Item.DirectoryName }
    elseif ($Sequence) { $base = $first.Item.Parent.FullName }
    else { $base = $first.Item.FullName }
    $OutputDir = Join-Path $base 'dlss5-test'
}
$toolDir = Join-Path $OutputDir 'for-tool'
$reviewDir = Join-Path $OutputDir 'for-review'
foreach ($d in @($OutputDir, $toolDir, $reviewDir)) {
    if (-not (Test-Path -LiteralPath $d)) { [void] (New-Item -ItemType Directory -Path $d) }
}
$script:LogPath = Join-Path $OutputDir 'conversion-log.csv'

Write-Host "ffmpeg:  $($script:Ffmpeg)"
Write-Host "Output:  $OutputDir"
$lookText = "exposure $(Format-Number $Exposure) stops, tone map $ToneMap"
if ($ToneMap -ne 'none') { $lookText += " (white point $(Format-Number $WhitePoint))" }
if ($Lut) { $lookText += ", LUT $Lut" }
Write-Host "Look:    $lookText"
Write-Host ''

# ---------------------------------------------------------------- run

$ok = 0
$failed = 0
$started = Get-Date

if ($Sequence) {
    foreach ($in in $inputs) {
        $shot = $in.Item.Name
        $frames = Get-ExrFiles $in.Item.FullName
        if ($frames.Count -eq 0) { Write-Warning "No .exr files in $($in.Item.FullName)"; continue }
        $frameDir = Join-Path $toolDir "$($shot)_frames"
        if (-not (Test-Path -LiteralPath $frameDir)) { [void] (New-Item -ItemType Directory -Path $frameDir) }
        Write-Host "Sequence $shot ($($frames.Count) frames)" -ForegroundColor Cyan
        $tiffs = @()
        $seqFailed = $false
        $i = 0
        foreach ($f in $frames) {
            $i++
            $tif = Join-Path $frameDir ([System.IO.Path]::ChangeExtension($f.Name, '.tif'))
            Write-Progress -Activity "Converting $shot" -Status $f.Name -PercentComplete ([int] (100 * $i / $frames.Count))
            try {
                $meta = Convert-ExrFile $f.FullName $tif
                $tiffs += $tif
                Add-LogRow $f.FullName $tif 'frame' $meta 'ok' ''
            } catch {
                $seqFailed = $true
                $failed++
                Add-LogRow $f.FullName $tif 'frame' $null 'failed' $_.Exception.Message
                Write-Host "  $($f.Name): FAILED - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        Write-Progress -Activity "Converting $shot" -Completed
        if ($seqFailed) {
            Write-Host "  Skipping the movie for $shot because some frames failed." -ForegroundColor Yellow
            continue
        }
        $movie = Join-Path $toolDir "$shot.mp4"
        try {
            Write-Host "  Encoding $shot.mp4 at $(Format-Number $Fps) fps..."
            Write-Movie $tiffs $movie
            Copy-Item -LiteralPath $movie -Destination (Join-Path $reviewDir "$shot.mp4") -Force
            Add-LogRow $in.Item.FullName $movie 'movie' $null 'ok' "$($tiffs.Count) frames"
            $ok++
            Write-Host "  ok: for-tool\$shot.mp4, for-review\$shot.mp4, $($tiffs.Count) TIFF frames" -ForegroundColor Green
        } catch {
            $failed++
            Add-LogRow $in.Item.FullName $movie 'movie' $null 'failed' $_.Exception.Message
            Write-Host "  movie FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
} else {
    $files = @()
    foreach ($in in $inputs) {
        if ($in.Kind -eq 'file') { $files += $in.Item } else { $files += Get-ExrFiles $in.Item.FullName }
    }
    if ($files.Count -eq 0) { throw 'No .exr files found.' }
    $i = 0
    foreach ($f in $files) {
        $i++
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $tif = Join-Path $toolDir "$stem.tif"
        $png = Join-Path $reviewDir "$stem.png"
        Write-Host ("[{0}/{1}] {2}" -f $i, $files.Count, $f.Name) -NoNewline
        try {
            $meta = Convert-ExrFile $f.FullName $tif
            Write-ReviewPng $tif $png
            Add-LogRow $f.FullName $tif 'still' $meta 'ok' ''
            $ok++
            Write-Host ("  ok  {0} x {1}, layer {2}" -f $meta.Width, $meta.Height, $meta.Layer) -ForegroundColor Green
        } catch {
            $failed++
            Add-LogRow $f.FullName $tif 'still' $null 'failed' $_.Exception.Message
            Write-Host "  FAILED - $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

$elapsed = [int] ((Get-Date) - $started).TotalSeconds
Write-Host ''
Write-Host "Done in $elapsed s: $ok ok, $failed failed. Log: $($script:LogPath)"
Write-Host "Next: run everything in for-tool through the community tool; load for-review as Originals in ab-review.html."
if ($failed -gt 0) { exit 1 }
