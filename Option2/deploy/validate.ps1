[CmdletBinding()]
param(
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$chart = Join-Path $PSScriptRoot 'helm\content-factory'
$exampleValues = Join-Path $chart 'values.example.yaml'
$bicep = Join-Path $repoRoot 'Option2\infra\aks\main.bicep'

az bicep build --file $bicep --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep validation failed.' }

helm lint $chart -f $exampleValues
if ($LASTEXITCODE -ne 0) { throw 'Helm lint failed.' }

helm template content-factory $chart -f $exampleValues | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Helm rendering failed.' }

if (-not $SkipTests) {
    $testProjects = @(
        @{ Name = 'BFF'; Path = 'Option2\Lab\src\bff' },
        @{ Name = 'Sandbox broker'; Path = 'Option2\Lab\src\sandbox-broker' },
        @{ Name = 'Research agent'; Path = 'Option2\Lab\src\agent-research' },
        @{ Name = 'Podcaster agent'; Path = 'Option2\Lab\src\agent-podcaster' }
    )

    $previousOtelDisabled = $env:OTEL_SDK_DISABLED
    $env:OTEL_SDK_DISABLED = 'true'
    try {
        foreach ($project in $testProjects) {
            Push-Location (Join-Path $repoRoot $project.Path)
            try {
                python -m pytest tests -q
                if ($LASTEXITCODE -ne 0) { throw "$($project.Name) tests failed." }
            }
            finally {
                Pop-Location
            }
        }
    }
    finally {
        $env:OTEL_SDK_DISABLED = $previousOtelDisabled
    }

    dotnet test (Join-Path $repoRoot 'Option2\Lab\src\agent-creator\AgentCreator.Tests\AgentCreator.Tests.csproj')
    if ($LASTEXITCODE -ne 0) { throw 'Creator-agent tests failed.' }
}

Write-Host 'ACA Sandbox Content Factory validation completed successfully.'
