param(
  [string]$OutputPath = "./artifacts/field-client-win-x64",
  [switch]$SelfContained
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "FieldClient.Windows/FieldClient.Windows.csproj"

dotnet restore $project --locked-mode
$publishArgs = @(
  "publish", $project,
  "--configuration", "Release",
  "--runtime", "win-x64",
  "--output", $OutputPath,
  "-p:PublishSingleFile=true",
  "-p:IncludeNativeLibrariesForSelfExtract=true"
)
if ($SelfContained) { $publishArgs += "--self-contained"; $publishArgs += "true" }
else { $publishArgs += "--self-contained"; $publishArgs += "false" }

& dotnet @publishArgs
Write-Host "Windows field client published to $OutputPath"
