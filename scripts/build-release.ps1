param(
  [string]$Version = "1.4.0",
  [string]$LazbuildPath = "C:\Lazarus\lazarus\lazbuild.exe"
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Push-Location $RootDir
try {
  Write-Host "[1/4] Compilando e executando testes unitarios..."
  & $LazbuildPath "tests\MultiDbSqlEditorTests.lpi"
  if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar testes." }
  & ".\tests\bin\MultiDbSqlEditorTests.exe" --all --format=plain
  if ($LASTEXITCODE -ne 0) { throw "Testes unitarios falharam." }

  Write-Host "[2/4] Compilando MultiDbSqlEditor (Release)..."
  & $LazbuildPath --build-mode=Release "MultiDbSqlEditor.lpi"
  if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar MultiDbSqlEditor." }

  Write-Host "[3/4] Montando pacote Win64..."
  $StageDir = Join-Path $env:TEMP "MultiDbSqlEditor-v$Version-win64-stage"
  $ReleaseDir = Join-Path $RootDir "release"
  $ZipPath = Join-Path $ReleaseDir "MultiDbSqlEditor-v$Version-win64.zip"

  if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
  if (-not (Test-Path $ReleaseDir)) { New-Item -ItemType Directory -Path $ReleaseDir | Out-Null }
  if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

  New-Item -ItemType Directory -Path $StageDir | Out-Null
  Copy-Item (Join-Path $RootDir "bin\MultiDbSqlEditor.exe") -Destination $StageDir
  Copy-Item (Join-Path $RootDir "README.md") -Destination $StageDir
  Copy-Item (Join-Path $RootDir "ARQUITETURA.md") -Destination $StageDir
  Copy-Item (Join-Path $RootDir "bin\clients") -Destination (Join-Path $StageDir "clients") -Recurse

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $StageDir,
    $ZipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
  )
  Remove-Item $StageDir -Recurse -Force

  $ZipInfo = Get-Item $ZipPath
  Write-Host "[4/4] Pacote gerado: $($ZipInfo.FullName) ($($ZipInfo.Length) bytes)"
}
finally {
  Pop-Location
}
