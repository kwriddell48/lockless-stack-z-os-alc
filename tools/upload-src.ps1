<#
.SYNOPSIS
  Upload src/ to Z72675.STACK.ASM and Z72675.STACK.MAC via Zowe.

.DESCRIPTION
  *.asm  -> HLQ.STACK.ASM(member)
  *.mac  -> HLQ.STACK.MAC(member)
  *.inc  -> HLQ.STACK.MAC(member)

  ASMA90 SYSLIB must include STACK.MAC so COPY ATOMICS / DSECTS /
  REGEQUAT / COPY64 / SAVEMAC / TRACE resolve. Allocate with
  jcl/stkalloc.jcl.

  Member name is the file basename, uppercased, truncated to 8 chars.

.PARAMETER Hlq
  High-level qualifier. Default Z72675.

.PARAMETER DryRun
  Print the mapping; do not call Zowe.
#>
[CmdletBinding()]
param(
    [string]$Hlq = 'Z72675',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SrcDir = Join-Path $RepoRoot 'src'
$PdsAsm = "$Hlq.STACK.ASM"
$PdsMac = "$Hlq.STACK.MAC"

function Get-MemberName([string]$Path) {
    $name = [IO.Path]::GetFileNameWithoutExtension($Path).ToUpperInvariant()
    if ($name.Length -gt 8) { $name = $name.Substring(0, 8) }
    return $name
}

function Invoke-ZoweUpload([string]$Local, [string]$Dsn) {
    Write-Host "  $Local"
    Write-Host "    -> $Dsn"
    if ($DryRun) { return }
    & zowe zos-files upload file-to-data-set $Local $Dsn --encoding IBM-1047
    if ($LASTEXITCODE -ne 0) {
        throw "Zowe upload failed: $Dsn (exit $LASTEXITCODE)"
    }
}

if (-not (Get-Command zowe -ErrorAction SilentlyContinue)) {
    throw 'zowe is not on PATH. Install Zowe CLI and log in (zowe auth login) first.'
}
if (-not (Test-Path -LiteralPath $SrcDir)) {
    throw "src folder not found: $SrcDir"
}

$asm = @(Get-ChildItem -LiteralPath $SrcDir -File -Filter '*.asm' | Sort-Object Name)
$mac = @(Get-ChildItem -LiteralPath $SrcDir -File -Filter '*.mac' | Sort-Object Name)
$inc = @(Get-ChildItem -LiteralPath $SrcDir -File -Filter '*.inc' | Sort-Object Name)

Write-Host "Uploading src -> $PdsAsm / $PdsMac"
Write-Host ''

foreach ($f in $asm) {
    $mem = Get-MemberName $f.FullName
    Invoke-ZoweUpload $f.FullName "$PdsAsm($mem)"
}

foreach ($f in ($mac + $inc)) {
    $mem = Get-MemberName $f.FullName
    Invoke-ZoweUpload $f.FullName "$PdsMac($mem)"
}

Write-Host ''
Write-Host ("Done. {0} ASM, {1} MAC, {2} INC." -f $asm.Count, $mac.Count, $inc.Count)
if ($DryRun) { Write-Host 'Dry run; nothing sent.' }
