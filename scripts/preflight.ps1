# preflight.ps1 - ds-vision-skill-plus channel availability matrix.
# Read-only: no external network calls (only local port probes).
# ASCII-only source.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

function Test-Port([int]$Port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(500) -and $client.Connected) { return 'open' }
    } catch { }
    finally { $client.Close() }
    return 'closed'
}

function Get-EnvValue([string]$Name) {
    $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
    return $v
}

Write-Output '## DS Vision Skill Plus - Preflight'
Write-Output ''

Write-Output '### System'
$gpu = Get-CimInstance Win32_VideoController | Sort-Object AdapterRAM -Descending | Select-Object -First 1
if ($gpu) {
    $vramGB = [Math]::Round($gpu.AdapterRAM / 1GB, 1)
    Write-Output ("- GPU: {0}; VRAM: {1} GB" -f $gpu.Name, $vramGB)
}
$ramGB = [Math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 0)
Write-Output ("- CPU cores: {0}; RAM: {1} GB" -f $env:NUMBER_OF_PROCESSORS, $ramGB)
Write-Output ''

Write-Output '### Tools'
foreach ($tool in @('mineru-open-api','llmfit','uvx','ollama','docker')) {
    $found = Get-Command $tool -ErrorAction SilentlyContinue
    Write-Output ("- {0}: {1}" -f $tool, $(if ($found) { 'OK' } else { 'not found' }))
}
Write-Output ''

Write-Output '### Local runtimes (port probe)'
Write-Output ("- ollama 11434: {0}" -f (Test-Port 11434))
Write-Output ("- lmstudio 1234: {0}" -f (Test-Port 1234))
Write-Output ("- llamacpp 8080: {0}" -f (Test-Port 8080))
Write-Output ''

$channels = [ordered]@{
    'custom (default vision)'                  = 'VISION_CUSTOM_API_KEY'
    'glm (4V-Flash fallback)'                = 'GLM_API_KEY'
    'glm-thinking (4.1V-Thinking fallback)'  = 'GLM_API_KEY'
    'baidu-ocr (general/accurate)'           = 'BAIDU_API_KEY'
}

Write-Output '### Cloud channels (env keys)'
foreach ($name in $channels.Keys) {
    $keyName = $channels[$name]
    $set = [bool](Get-EnvValue $keyName)
    Write-Output ("- {0}: {1}" -f $name, $(if ($set) { 'OK (key set)' } else { 'dormant (no key)' }))
}
if ((Get-EnvValue 'VISION_CUSTOM_BASE_URL') -and (Get-EnvValue 'VISION_CUSTOM_MODEL')) {
    Write-Output ("- custom vision: base={0} model={1}" -f (Get-EnvValue 'VISION_CUSTOM_BASE_URL'), (Get-EnvValue 'VISION_CUSTOM_MODEL'))
}
Write-Output ''

Write-Output '### Image generation (images/generations)'
$genOk = (Get-EnvValue 'VISION_GEN_API_KEY') -and (Get-EnvValue 'VISION_GEN_BASE_URL') -and (Get-EnvValue 'VISION_GEN_MODEL')
Write-Output ("- image-gen: {0}" -f $(if ($genOk) { 'configured' } else { 'dormant (missing config)' }))
if ($genOk) { Write-Output ("  endpoint: {0}/v1/images/generations model={1}" -f (Get-EnvValue 'VISION_GEN_BASE_URL'), (Get-EnvValue 'VISION_GEN_MODEL')) }
Write-Output ''

Write-Output '### Category routing (first available)'
Write-Output '- image_reasoning: custom (default, user-configured) -> glm (simple) -> glm-thinking (complex) -> local'
Write-Output '- image_generation: image-gen (VISION_GEN_* configured; no free fallback)'
Write-Output '- document_parsing: mineru flash -> mineru extract'
Write-Output '- ocr: baidu-ocr -> windows-ocr (local) -> mineru'
Write-Output '- local: llmfit selection -> ollama/lmstudio/llamacpp'
Write-Output '- custom: VISION_CUSTOM_* if configured'
