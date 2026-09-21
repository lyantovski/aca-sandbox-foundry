# Architecture Diagrams

The Mermaid sources are the concise documentation source of truth. The
Excalidraw and Draw.io files provide editable presentation and engineering
views of the same deployed architecture. SVG files are embedded in the
documentation, and PNG files are provided for presentations.

| Diagram | Mermaid | Excalidraw | Draw.io | Editable-layout preview | SVG | PNG |
|---|---|---|---|---|---|---|
| System architecture | [`system-architecture.mmd`](system-architecture.mmd) | [`system-architecture.excalidraw`](system-architecture.excalidraw) | [`system-architecture.drawio`](system-architecture.drawio) | [`system-architecture.editable-preview.svg`](system-architecture.editable-preview.svg) | [`system-architecture.svg`](system-architecture.svg) | [`system-architecture.png`](system-architecture.png) |
| Network design | [`network-design.mmd`](network-design.mmd) | [`network-design.excalidraw`](network-design.excalidraw) | [`network-design.drawio`](network-design.drawio) | [`network-design.editable-preview.svg`](network-design.editable-preview.svg) | [`network-design.svg`](network-design.svg) | [`network-design.png`](network-design.png) |
| Execution flow | [`execution-flow.mmd`](execution-flow.mmd) | - | - | - | [`execution-flow.svg`](execution-flow.svg) | [`execution-flow.png`](execution-flow.png) |

Open `.excalidraw` files with the Microsoft-hosted editor at
`https://aka.ms/excalidraw`. Open `.drawio` files with diagrams.net, the Draw.io
desktop application, or the VS Code Draw.io integration.

Regenerate the Mermaid exports from the repository root:

```powershell
.\docs\diagrams\render.ps1
```

Regenerate the editable Excalidraw and Draw.io sources:

```powershell
node .\docs\diagrams\generate-editable-diagrams.mjs
```

The generator is deterministic and keeps matching elements, labels, colors,
and network addresses aligned between both editable formats. It rejects
diagrams containing diagonal connectors, connectors that cross component
boxes, or connectors that cross or overlap each other. The editable-layout
preview uses the same coordinates and routing as the Excalidraw and Draw.io
files.
