param(
  [string]$OutputPath = "./artifacts/field-client-win-x64",
  [bool]$SelfContained = $true
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "FieldClient.Windows/FieldClient.Windows.csproj"

dotnet restore $project --locked-mode
$publishArgs = @(
  "publish", $project,
  "--configuration", "Release",
  "--runtime", "win-x64",
  "--output", $OutputPath,
  "--self-contained", $SelfContained.ToString().ToLowerInvariant(),
  "-p:PublishSingleFile=true",
  "-p:IncludeNativeLibrariesForSelfExtract=true",
  "-p:DebugType=None",
  "-p:DebugSymbols=false"
)

& dotnet @publishArgs
Copy-Item (Join-Path $PSScriptRoot "README-WINDOWS.txt") (Join-Path $OutputPath "开始使用.txt") -Force
Write-Host "Windows field client published to $OutputPath"
