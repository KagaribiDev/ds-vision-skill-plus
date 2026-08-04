# image-gen.ps1 - OpenAI-compatible image generation (images/generations) for ds-vision-skill-plus.
# User configures the model via env vars (OpenAI-compatible spec):
#   VISION_GEN_BASE_URL (e.g. https://your-provider.example.com/v1)
#   VISION_GEN_API_KEY
#   VISION_GEN_MODEL
# Result is saved as a local PNG; -Json prints the standard envelope with the file path.
# ASCII-only source. Pass Chinese text via -Prompt; never embed non-ASCII here.
# Exit codes: 0 success, 1 generic, 2 missing config/auth, 3 rate-limited, 4 network, 5 request rejected.

param(
    [Parameter(Mandatory = $true)][string]$Prompt,
    [string]$Model = '',
    [string]$BaseUrl = '',
    [string]$ApiKey = '',
    [string]$Size = '1024x1024',
    [int]$N = 1,
    [string]$OutDir = '',
    [switch]$Json,
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Err([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Get-EnvValue([string]$Name) {
    $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
    return $v
}

function Get-DownloadsDir {
    # Resolve the real Downloads folder (handles OneDrive redirection);
    # falls back to %USERPROFILE%\Downloads.
    $dl = [Microsoft.Win32.Registry]::GetValue('HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders', '{374DE290-123F-4565-9164-39C4925E467B}', $null)
    if (-not $dl) { $dl = Join-Path $env:USERPROFILE 'Downloads' }
    return [string]$dl
}

# --- resolve config (user-provided params win; then env vars) ---
$resolvedKey = $ApiKey
if (-not $resolvedKey) { $resolvedKey = Get-EnvValue 'VISION_GEN_API_KEY' }
if (-not $resolvedKey) {
    Write-Err 'ERROR: image-gen API key missing. Set VISION_GEN_API_KEY or run setup.ps1 -SetGen -BaseUrl <url> -Key <key> -Model <model>.'
    exit 2
}

$resolvedModel = $Model
if (-not $resolvedModel) { $resolvedModel = Get-EnvValue 'VISION_GEN_MODEL' }
if (-not $resolvedModel) {
    Write-Err 'ERROR: image-gen model missing. Set VISION_GEN_MODEL or run setup.ps1 -SetGen -BaseUrl <url> -Key <key> -Model <model>.'
    exit 2
}

$resolvedBase = $BaseUrl
if (-not $resolvedBase) { $resolvedBase = Get-EnvValue 'VISION_GEN_BASE_URL' }
if (-not $resolvedBase) {
    Write-Err 'ERROR: image-gen base URL missing. Set VISION_GEN_BASE_URL or run setup.ps1 -SetGen -BaseUrl <url> -Key <key> -Model <model>.'
    exit 2
}

$base = $resolvedBase.TrimEnd('/')
# Robust endpoint resolution: accept either the root (auto-append /v1/images/generations)
# or a full endpoint that already ends with /images/generations.
if ($base -notmatch '/images/generations$') {
    if ($base -notmatch '/v1$') { $base += '/v1' }
    $base += '/images/generations'
}
$endpoint = $base

if (-not $OutDir) { $OutDir = Get-DownloadsDir }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$r = $null

# --- attempt 1: b64_json ---
$body = @{ model = $resolvedModel; prompt = $Prompt; n = $N; size = $Size; response_format = 'b64_json' } | ConvertTo-Json -Depth 5
try {
    $resp = Invoke-WebRequest -Uri $endpoint -Method Post -Headers @{ Authorization = "Bearer $resolvedKey" } -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec $TimeoutSec
    $sw.Stop()
    $ms = New-Object System.IO.MemoryStream
    $resp.RawContentStream.CopyTo($ms)
    $jsonText = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    $r = $jsonText | ConvertFrom-Json
} catch {
    $sw.Stop()
    $status = 0
    if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch { } }
    # Some providers reject b64_json; retry once with response_format=url.
    if ($status -eq 400 -or $status -eq 422) {
        Write-Err "WARN: b64_json rejected (status $status); retrying with response_format=url."
        $bodyUrl = @{ model = $resolvedModel; prompt = $Prompt; n = $N; size = $Size; response_format = 'url' } | ConvertTo-Json -Depth 5
        try {
            $sw.Restart()
            $resp = Invoke-WebRequest -Uri $endpoint -Method Post -Headers @{ Authorization = "Bearer $resolvedKey" } -ContentType 'application/json; charset=utf-8' -Body $bodyUrl -TimeoutSec $TimeoutSec
            $sw.Stop()
            $ms = New-Object System.IO.MemoryStream
            $resp.RawContentStream.CopyTo($ms)
            $jsonText = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $r = $jsonText | ConvertFrom-Json
        } catch {
            $status2 = 0
            if ($_.Exception.Response) { try { $status2 = [int]$_.Exception.Response.StatusCode } catch { } }
            if ($status2 -eq 401 -or $status2 -eq 403) {
                Write-Err "ERROR: image-gen status=$status2 auth failed."
                exit 2
            }
            if ($status2 -eq 429) {
                Write-Err "ERROR: image-gen status=429 rate limited."
                exit 3
            }
            if ($status2 -eq 0 -or $status2 -ge 500) {
                Write-Err "ERROR: image-gen status=$status2 network/server: $($_.Exception.Message)"
                exit 4
            }
            Write-Err "ERROR: image-gen status=$status2 request rejected: $($_.Exception.Message)"
            exit 5
        }
    } else {
        if ($status -eq 401 -or $status -eq 403) {
            Write-Err "ERROR: image-gen status=$status auth failed."
            exit 2
        }
        if ($status -eq 429) {
            Write-Err "ERROR: image-gen status=429 rate limited."
            exit 3
        }
        if ($status -eq 0 -or $status -ge 500) {
            Write-Err "ERROR: image-gen status=$status network/server: $($_.Exception.Message)"
            exit 4
        }
        Write-Err "ERROR: image-gen status=$status request rejected: $($_.Exception.Message)"
        exit 5
    }
}

if (-not $r.data -or -not $r.data[0]) {
    Write-Err 'ERROR: empty generation response.'
    exit 1
}

# --- obtain image bytes: b64_json directly, or url via download ---
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rand = -join ((48..57) + (97..102) | Get-Random -Count 8 | ForEach-Object { [char]$_ })
$outFile = Join-Path $OutDir ("image-$stamp-$rand.png")

$imageUrl = ''
$bytes = $null
if ($r.data[0].b64_json) {
    try {
        $bytes = [Convert]::FromBase64String([string]$r.data[0].b64_json)
    } catch {
        Write-Err "ERROR: invalid b64_json payload: $($_.Exception.Message)"
        exit 1
    }
    [IO.File]::WriteAllBytes($outFile, $bytes)
} elseif ($r.data[0].url) {
    $imageUrl = [string]$r.data[0].url
    try {
        Invoke-WebRequest -Uri $imageUrl -Method Get -OutFile $outFile -TimeoutSec $TimeoutSec
        $bytes = [IO.File]::ReadAllBytes($outFile)
    } catch {
        Write-Err "ERROR: failed to download generated image: $($_.Exception.Message)"
        exit 4
    }
} else {
    Write-Err 'ERROR: response contains neither b64_json nor url.'
    exit 1
}

$envelope = [ordered]@{
    task_type  = 'image_generation'
    tool_used  = "image-gen:$resolvedModel"
    confidence = 'high'
    result     = $outFile
    metadata   = [ordered]@{
        model      = $resolvedModel
        size       = $Size
        url        = $imageUrl
        out_file   = $outFile
        bytes      = $bytes.Length
        latency_ms = $sw.ElapsedMilliseconds
    }
}
if ($Json) {
    Write-Output ($envelope | ConvertTo-Json -Depth 5)
} else {
    Write-Output $outFile
}
exit 0
