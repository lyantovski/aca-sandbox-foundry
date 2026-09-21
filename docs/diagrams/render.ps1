[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$diagramRoot = $PSScriptRoot
$diagrams = @('system-architecture', 'network-design', 'execution-flow')

foreach ($diagram in $diagrams) {
    $source = Join-Path $diagramRoot "$diagram.mmd"
    $svg = Join-Path $diagramRoot "$diagram.svg"
    $png = Join-Path $diagramRoot "$diagram.png"

    npx --yes @mermaid-js/mermaid-cli -i $source -o $svg -b transparent
    if ($LASTEXITCODE -ne 0) { throw "Unable to render $source as SVG." }

    npx --yes @mermaid-js/mermaid-cli -i $source -o $png -b transparent -w 2400
    if ($LASTEXITCODE -ne 0) { throw "Unable to render $source as PNG." }
}

Write-Host 'Architecture diagram exports generated successfully.'
