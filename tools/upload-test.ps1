<#
.SYNOPSIS
  Upload TEST/ to Z72675.STACK.C and Z72675.STACK.H via Zowe.

.DESCRIPTION
  *.c    -> HLQ.STACK.C(member)
  *.h    -> HLQ.STACK.H(member)
  *.asm  -> HLQ.STACK.ASM(member)   (CGLUE, TESTCB)

  Member name is the file basename, uppercased, truncated to 8 chars
  (t09varlen.c -> T09VARLE). Does not upload jcl/ or README.md.

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
$TestDir = Join-Path $RepoRoot 'TEST'
$PdsC = "$Hlq.STACK.C"
$PdsH = "$Hlq.STACK.H"
$PdsAsm = "$Hlq.STACK.ASM"

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
if (-not (Test-Path -LiteralPath $TestDir)) {
    throw "TEST folder not found: $TestDir"
}

$cFiles = @(Get-ChildItem -LiteralPath $TestDir -File -Filter '*.c' | Sort-Object Name)
$hFiles = @(Get-ChildItem -LiteralPath $TestDir -File -Filter '*.h' | Sort-Object Name)
$asmFiles = @(Get-ChildItem -LiteralPath $TestDir -File -Filter '*.asm' | Sort-Object Name)

Write-Host "Uploading TEST -> $PdsC / $PdsH / $PdsAsm"
Write-Host ''

foreach ($f in $cFiles) {
    $mem = Get-MemberName $f.FullName
    Invoke-ZoweUpload $f.FullName "$PdsC($mem)"
}

foreach ($f in $hFiles) {
    $mem = Get-MemberName $f.FullName
    Invoke-ZoweUpload $f.FullName "$PdsH($mem)"
}

foreach ($f in $asmFiles) {
    $mem = Get-MemberName $f.FullName
    Invoke-ZoweUpload $f.FullName "$PdsAsm($mem)"
}

Write-Host ''
Write-Host ("Done. {0} C, {1} H, {2} ASM." -f $cFiles.Count, $hFiles.Count, $asmFiles.Count)
if ($DryRun) { Write-Host 'Dry run; nothing sent.' }
