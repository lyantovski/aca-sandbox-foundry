import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(fileURLToPath(import.meta.url));

const palette = {
  blue: { stroke: "#0078D4", fill: "#CFE4FA" },
  green: { stroke: "#107C10", fill: "#DFF6DD" },
  orange: { stroke: "#F7630C", fill: "#FFF4CE" },
  purple: { stroke: "#5C2D91", fill: "#E8DAEF" },
  red: { stroke: "#D13438", fill: "#FDE7E9" },
  gray: { stroke: "#605E5C", fill: "#F3F2F1" },
  teal: { stroke: "#038387", fill: "#D7F0F0" },
  white: { stroke: "#A19F9D", fill: "#FFFFFF" },
};

const node = (id, label, x, y, width, height, color, options = {}) => ({
  id,
  label,
  x,
  y,
  width,
  height,
  color,
  container: false,
  ...options,
});

const container = (id, label, x, y, width, height, color) =>
  node(id, label, x, y, width, height, color, { container: true });

const port = (side, offset = 0.5) => ({ side, offset });

const edge = (
  id,
  from,
  fromPort,
  to,
  toPort,
  color,
  waypoints = [],
  options = {},
) => ({
  id,
  from,
  fromPort,
  to,
  toPort,
  color,
  waypoints,
  dashed: false,
  bidirectional: false,
  label: "",
  labelBox: null,
  ...options,
});

function legendNodes(y, width) {
  const left = 40;
  const itemWidth = 215;
  const gap = 14;
  const row1 = [
    ["legend-ui", "Blue fill\nUI and edge", "blue"],
    ["legend-governance", "Purple fill\nIdentity and governance", "purple"],
    ["legend-runtime", "Green fill\nAKS agent runtime", "green"],
    ["legend-managed", "Orange fill\nManaged data and execution", "orange"],
    ["legend-observe", "Teal fill\nObservability", "teal"],
  ];
  const row2 = [
    ["legend-app-flow", "Blue solid\nApplication and A2A", "blue"],
    ["legend-control-flow", "Purple dashed\nIdentity and registration", "purple"],
    ["legend-model-flow", "Green solid\nModel inference", "green"],
    ["legend-data-flow", "Orange solid\nSandbox and storage", "orange"],
    ["legend-telemetry-flow", "Teal dashed\nTelemetry", "teal"],
  ];

  return [
    container("legend", "LEGEND", left, y, width - 80, 175, "gray"),
    node("legend-component-heading", "COMPONENT\nFILL", left + 20, y + 30, 125, 50, "gray"),
    node("legend-flow-heading", "CONNECTOR\nMEANING", left + 20, y + 105, 125, 50, "gray"),
    ...row1.map(([id, label, color], index) =>
      node(id, label, left + 170 + index * (itemWidth + gap), y + 25, itemWidth, 58, color),
    ),
    ...row2.map(([id, label, color], index) =>
      node(
        id,
        label,
        left + 170 + index * (itemWidth + gap),
        y + 100,
        itemWidth,
        58,
        color,
        { dashedBorder: id === "legend-control-flow" || id === "legend-telemetry-flow" },
      ),
    ),
  ];
}

const system = {
  name: "System Architecture",
  subtitle: "Phase 1 runtime paths - browser orchestration, governed A2A, model access, sandbox execution, and telemetry",
  width: 2400,
  height: 1380,
  nodes: [
    container("client-zone", "USER AND IDENTITY", 40, 255, 390, 825, "blue"),
    container("aks-zone", "AKS CONTENT FACTORY", 450, 255, 1300, 825, "green"),
    container("azure-zone", "AI GATEWAY AND MANAGED SERVICES", 1790, 255, 570, 825, "purple"),

    node("user", "User", 80, 475, 120, 70, "blue"),
    node("browser", "Browser\nDevUI JavaScript orchestrator", 230, 455, 180, 110, "blue"),
    node("entra", "Microsoft Entra ID", 110, 700, 220, 90, "purple"),

    node("agc", "Application Gateway\nfor Containers", 470, 470, 180, 100, "blue"),
    node("devui", "DevUI NGINX\nstatic HTML and JavaScript", 720, 330, 200, 100, "blue"),
    node("oauth", "OAuth2 Proxy\nOIDC session", 720, 500, 200, 100, "purple"),
    node("bff", "BFF\ntrusted browser boundary", 980, 500, 180, 100, "purple"),
    node("apim-a2a", "APIM governed A2A APIs\nresearch, creator, podcaster", 1220, 475, 220, 140, "purple"),
    node("research", "Research Agent\nA2A and LangGraph\ncalls Sandbox Broker", 1510, 350, 180, 100, "green"),
    node("creator", "Creator Agent\nA2A and MAF", 1510, 525, 180, 100, "green"),
    node("podcaster", "Podcaster Agent\nA2A and Copilot SDK", 1510, 700, 180, 100, "green"),
    node(
      "orchestration-note",
      "Browser orchestration\nResearch first, then creator and podcaster in parallel\nNo direct agent-to-agent calls",
      720,
      760,
      420,
      110,
      "gray",
    ),
    node("broker", "Sandbox Broker\ncalled only by Research\nWorkload Identity", 1220, 890, 220, 100, "orange"),
    node("otel", "OpenTelemetry Collector\nBFF, agents, and broker", 1510, 980, 180, 90, "teal"),

    node("registry", "Foundry custom-agent\nregistry", 1840, 330, 200, 100, "purple"),
    node("apim-model", "APIM model gateway\n/openai", 1840, 525, 200, 100, "purple"),
    node("models", "Foundry Models\nGPT-4o and TTS", 2110, 525, 200, 100, "blue"),
    node("sandboxes", "ACA Sandbox Group\nisolated retrieval", 1840, 890, 200, 100, "orange"),
    node("blob", "Private Blob Storage\npodcast persistence", 2110, 700, 200, 100, "orange"),
    node("insights", "Application Insights\nOTEL export and APIM diagnostics", 2110, 980, 200, 90, "teal"),

    ...legendNodes(1160, 2400),
  ],
  edges: [
    edge("s1", "user", port("right"), "browser", port("left"), "blue", [], {
      label: "1  Uses",
      labelBox: { x: 185, y: 420, width: 75 },
    }),
    edge("s2", "browser", port("right"), "agc", port("left"), "blue", [{ x: 440, y: 510 }, { x: 440, y: 520 }], {
      label: "2  HTTPS / and /api",
      labelBox: { x: 385, y: 415, width: 145 },
    }),
    edge(
      "s3",
      "agc",
      port("top"),
      "devui",
      port("left"),
      "blue",
      [{ x: 560, y: 380 }, { x: 690, y: 380 }],
      {
        bidirectional: true,
        label: "3  Static UI",
        labelBox: { x: 570, y: 335, width: 110 },
      },
    ),
    edge(
      "s4",
      "browser",
      port("bottom"),
      "entra",
      port("top"),
      "purple",
      [{ x: 320, y: 645 }, { x: 220, y: 645 }],
      {
        dashed: true,
        bidirectional: true,
        label: "4  OIDC sign-in",
        labelBox: { x: 195, y: 610, width: 125 },
      },
    ),
    edge("s5", "agc", port("right", 0.8), "oauth", port("left"), "purple", [], {
      label: "5  /api and /oauth2",
      labelBox: { x: 610, y: 610, width: 135 },
    }),
    edge("s6", "oauth", port("right"), "bff", port("left"), "blue", [], {
      label: "6  Trusted identity",
      labelBox: { x: 910, y: 450, width: 130 },
    }),
    edge("s7", "bff", port("right"), "apim-a2a", port("left"), "blue", [{ x: 1190, y: 550 }, { x: 1190, y: 545 }], {
      label: "7  Governed A2A",
      labelBox: { x: 1150, y: 640, width: 130 },
    }),
    edge(
      "s8",
      "registry",
      port("left"),
      "apim-a2a",
      port("top"),
      "purple",
      [{ x: 1780, y: 380 }, { x: 1780, y: 300 }, { x: 1330, y: 300 }, { x: 1330, y: 445 }],
      {
        dashed: true,
        label: "Registered governed URLs",
        labelBox: { x: 1500, y: 285, width: 175 },
      },
    ),
    edge(
      "s9a",
      "apim-a2a",
      port("right", 0.25),
      "research",
      port("left"),
      "blue",
      [{ x: 1470, y: 510 }, { x: 1470, y: 400 }],
      {
        label: "8  Private origins 8001-8003",
        labelBox: { x: 1220, y: 680, width: 190 },
      },
    ),
    edge(
      "s9b",
      "apim-a2a",
      port("right", 0.5),
      "creator",
      port("left"),
      "blue",
      [{ x: 1470, y: 545 }, { x: 1470, y: 575 }],
    ),
    edge(
      "s9c",
      "apim-a2a",
      port("right", 0.75),
      "podcaster",
      port("left"),
      "blue",
      [{ x: 1470, y: 580 }, { x: 1470, y: 750 }],
    ),
    edge(
      "s10a",
      "research",
      port("right"),
      "apim-model",
      port("left", 0.3),
      "green",
      [{ x: 1770, y: 400 }, { x: 1770, y: 555 }],
      {
        label: "9  Model inference",
        labelBox: { x: 1690, y: 430, width: 140 },
      },
    ),
    edge("s10b", "creator", port("right"), "apim-model", port("left", 0.5), "green"),
    edge(
      "s10c",
      "podcaster",
      port("right", 0.3),
      "apim-model",
      port("left", 0.7),
      "green",
      [{ x: 1770, y: 730 }, { x: 1770, y: 595 }],
      {
        label: "Model and TTS",
        labelBox: { x: 1690, y: 665, width: 120 },
      },
    ),
    edge("s11", "apim-model", port("right"), "models", port("left"), "green", [], {
      label: "Managed identity",
      labelBox: { x: 2030, y: 535, width: 120 },
    }),
    edge("s13", "broker", port("right"), "sandboxes", port("left"), "orange", [], {
      label: "10  Create and execute",
      labelBox: { x: 1580, y: 915, width: 155 },
    }),
    edge("s14", "podcaster", port("right", 0.7), "blob", port("left"), "orange", [{ x: 2050, y: 770 }, { x: 2050, y: 750 }], {
      label: "11  Private Blob",
      labelBox: { x: 1830, y: 775, width: 125 },
    }),
    edge("s15", "otel", port("right"), "insights", port("left"), "teal", [], {
      dashed: true,
      label: "12  OTLP export",
      labelBox: { x: 1830, y: 1005, width: 120 },
    }),
  ],
};

const network = {
  name: "Network Design",
  subtitle: "Address boundaries and traffic paths - all agent origins remain private and accept APIM subnet sources only",
  width: 2400,
  height: 1540,
  nodes: [
    container("external-zone", "EXTERNAL CLIENT AND AZURE SERVICES", 40, 110, 2320, 175, "blue"),
    container("vnet-zone", "LAB VNET 10.40.0.0/16", 40, 330, 2320, 850, "green"),
    container("agc-subnet", "AGC SUBNET 10.40.16.0/24", 80, 400, 280, 700, "blue"),
    container("aks-subnet", "AKS SUBNET 10.40.0.0/20", 400, 400, 1000, 700, "green"),
    container("apim-subnet", "APIM SUBNET 10.40.18.0/24", 1440, 400, 400, 700, "purple"),
    container("pe-subnet", "PRIVATE ENDPOINTS 10.40.17.0/24", 1880, 400, 360, 700, "orange"),

    node("n-browser", "Browser\nDevUI JavaScript", 80, 165, 170, 80, "blue"),
    node("n-entra", "Microsoft Entra ID", 330, 165, 180, 80, "purple"),
    node("n-sandbox-service", "ACA Sandbox Service", 1930, 165, 170, 80, "orange"),
    node("n-foundry-registry", "Foundry Agent Registry", 1470, 165, 190, 80, "purple"),
    node("n-foundry-models", "Foundry Models", 1740, 165, 170, 80, "blue"),
    node("n-insights", "Application Insights", 2170, 165, 170, 80, "teal"),

    node("n-agc", "AGC frontend\nHTTPS 443", 130, 520, 180, 100, "blue"),
    node("n-devui", "DevUI NGINX\nHTTP 8080", 460, 480, 180, 90, "blue"),
    node("n-auth-bff", "OAuth2 Proxy :4180\nBFF :8081", 700, 480, 200, 110, "purple"),
    node("n-broker", "Research-only Sandbox Broker\nHTTP 8010", 700, 930, 200, 90, "orange"),
    node("n-otel", "OTEL Collector\nOTLP 4317", 460, 930, 180, 90, "teal"),

    node("n-research-origin", "Research private origin - calls broker\nILB 10.40.15.240:8001", 1050, 640, 300, 90, "green"),
    node("n-creator-origin", "Creator private origin\nILB 10.40.15.241:8002", 1050, 780, 300, 90, "green"),
    node("n-podcaster-origin", "Podcaster private origin\nILB 10.40.15.242:8003", 1050, 920, 300, 90, "green"),
    node(
      "n-origin-bus",
      "APIM-only\norigin routes\nTCP 8001\nTCP 8002\nTCP 8003",
      900,
      620,
      110,
      380,
      "red",
    ),

    node("n-apim-a2a", "APIM A2A APIs\nHTTPS 443", 1510, 530, 240, 120, "purple"),
    node("n-apim-model", "APIM /openai\nHTTPS 443", 1510, 820, 240, 110, "purple"),
    node("n-blob-pe", "Blob private endpoint\n10.40.17.4:443", 1950, 820, 220, 100, "orange"),
    node(
      "n-network-note",
      "Only AGC is public\nAgent load balancers are internal\nStorage public access is disabled",
      1930,
      500,
      260,
      130,
      "gray",
    ),

    ...legendNodes(1340, 2400),
  ],
  edges: [
    edge(
      "n1",
      "n-browser",
      port("bottom", 0.35),
      "n-agc",
      port("top"),
      "blue",
      [{ x: 139.5, y: 310 }, { x: 220, y: 310 }],
      {
        label: "1  HTTPS 443",
        labelBox: { x: 150, y: 300, width: 105 },
      },
    ),
    edge("n2", "n-agc", port("right", 0.3), "n-devui", port("left"), "blue", [{ x: 380, y: 550 }, { x: 380, y: 525 }], {
      bidirectional: true,
      label: "2  GET / and HTML",
      labelBox: { x: 330, y: 505, width: 125 },
    }),
    edge(
      "n3",
      "n-agc",
      port("bottom", 0.7),
      "n-auth-bff",
      port("bottom"),
      "purple",
      [{ x: 256, y: 640 }, { x: 800, y: 640 }],
      {
        label: "3  /api and /oauth2",
        labelBox: { x: 500, y: 605, width: 135 },
      },
    ),
    edge(
      "n4",
      "n-auth-bff",
      port("top"),
      "n-entra",
      port("bottom"),
      "purple",
      [{ x: 800, y: 350 }, { x: 420, y: 350 }],
      {
        dashed: true,
        bidirectional: true,
        label: "4  OIDC redirect and callback",
        labelBox: { x: 520, y: 305, width: 190 },
      },
    ),
    edge(
      "n5",
      "n-auth-bff",
      port("right", 0.35),
      "n-apim-a2a",
      port("left", 0.35),
      "blue",
      [{ x: 960, y: 518.5 }, { x: 960, y: 572 }, { x: 1460, y: 572 }],
      {
        label: "5  Governed A2A HTTPS",
        labelBox: { x: 1160, y: 525, width: 165 },
      },
    ),
    edge(
      "n6",
      "n-foundry-registry",
      port("bottom"),
      "n-apim-a2a",
      port("top"),
      "purple",
      [{ x: 1565, y: 330 }, { x: 1630, y: 330 }],
      {
        dashed: true,
        label: "Registered APIs",
        labelBox: { x: 1540, y: 300, width: 110 },
      },
    ),
    edge(
      "n7",
      "n-apim-a2a",
      port("left", 0.65),
      "n-origin-bus",
      port("top"),
      "blue",
      [{ x: 1460, y: 608 }, { x: 1460, y: 600 }, { x: 955, y: 600 }],
      {
        label: "6  APIM subnet to source-restricted private ILBs",
        labelBox: { x: 1070, y: 555, width: 285 },
      },
    ),
    edge(
      "n7a",
      "n-origin-bus",
      port("right", 47 / 380),
      "n-research-origin",
      port("left", 0.3),
      "blue",
    ),
    edge(
      "n7b",
      "n-origin-bus",
      port("right", 187 / 380),
      "n-creator-origin",
      port("left", 0.3),
      "blue",
    ),
    edge(
      "n7c",
      "n-origin-bus",
      port("right", 327 / 380),
      "n-podcaster-origin",
      port("left", 0.3),
      "blue",
    ),
    edge(
      "n8a",
      "n-research-origin",
      port("right", 0.75),
      "n-apim-model",
      port("left", 0.25),
      "green",
      [{ x: 1380, y: 707.5 }, { x: 1380, y: 800 }, { x: 1480, y: 800 }, { x: 1480, y: 847.5 }],
      {
        label: "7  Model HTTPS",
        labelBox: { x: 1360, y: 755, width: 115 },
      },
    ),
    edge(
      "n8b",
      "n-creator-origin",
      port("right", 0.75),
      "n-apim-model",
      port("left", 0.5),
      "green",
      [{ x: 1420, y: 847.5 }, { x: 1420, y: 875 }],
    ),
    edge(
      "n8c",
      "n-podcaster-origin",
      port("right", 0.75),
      "n-apim-model",
      port("left", 0.75),
      "green",
      [{ x: 1460, y: 987.5 }, { x: 1460, y: 902.5 }],
      {
        label: "Model and TTS",
        labelBox: { x: 1370, y: 945, width: 110 },
      },
    ),
    edge(
      "n9",
      "n-apim-model",
      port("top"),
      "n-foundry-models",
      port("bottom"),
      "green",
      [{ x: 1630, y: 740 }, { x: 1825, y: 740 }, { x: 1825, y: 300 }],
      {
        label: "8  Managed identity",
        labelBox: { x: 1670, y: 695, width: 135 },
      },
    ),
    edge(
      "n11",
      "n-broker",
      port("bottom"),
      "n-sandbox-service",
      port("bottom"),
      "orange",
      [{ x: 800, y: 1200 }, { x: 2220, y: 1200 }, { x: 2220, y: 300 }, { x: 2015, y: 300 }],
      {
        label: "9  Sandbox API",
        labelBox: { x: 1980, y: 1155, width: 120 },
      },
    ),
    edge(
      "n12",
      "n-podcaster-origin",
      port("bottom", 0.8),
      "n-blob-pe",
      port("bottom", 0.5),
      "orange",
      [{ x: 1290, y: 1120 }, { x: 2060, y: 1120 }],
      {
        label: "10  Private HTTPS",
        labelBox: { x: 1640, y: 1080, width: 135 },
      },
    ),
    edge(
      "n13",
      "n-otel",
      port("bottom"),
      "n-insights",
      port("bottom"),
      "teal",
      [{ x: 550, y: 1250 }, { x: 2300, y: 1250 }, { x: 2300, y: 300 }, { x: 2255, y: 300 }],
      {
        dashed: true,
        label: "11  OTLP and platform diagnostics",
        labelBox: { x: 1650, y: 1207, width: 220 },
      },
    ),
  ],
};

function endpoint(item, endpointPort) {
  const offset = endpointPort.offset ?? 0.5;
  switch (endpointPort.side) {
    case "left":
      return { x: item.x, y: item.y + item.height * offset };
    case "right":
      return { x: item.x + item.width, y: item.y + item.height * offset };
    case "top":
      return { x: item.x + item.width * offset, y: item.y };
    case "bottom":
      return { x: item.x + item.width * offset, y: item.y + item.height };
    default:
      throw new Error(`Unknown port side: ${endpointPort.side}`);
  }
}

function edgePoints(diagram, item) {
  const byId = new Map(diagram.nodes.map((candidate) => [candidate.id, candidate]));
  return [
    endpoint(byId.get(item.from), item.fromPort),
    ...item.waypoints,
    endpoint(byId.get(item.to), item.toPort),
  ];
}

function portStyle(prefix, endpointPort) {
  const offset = endpointPort.offset ?? 0.5;
  const values = {
    left: [0, offset],
    right: [1, offset],
    top: [offset, 0],
    bottom: [offset, 1],
  }[endpointPort.side];
  return `${prefix}X=${values[0]};${prefix}Y=${values[1]};${prefix}Dx=0;${prefix}Dy=0;${prefix}Perimeter=1;`;
}

const baseElement = (id) => ({
  id,
  type: "rectangle",
  angle: 0,
  strokeWidth: 2,
  strokeStyle: "solid",
  roughness: 0,
  opacity: 100,
  groupIds: [],
  frameId: null,
  roundness: { type: 3 },
  seed: Math.abs([...id].reduce(
    (sum, char) => ((sum * 31 + char.charCodeAt(0)) | 0),
    7,
  )) || 1,
  version: 1,
  versionNonce: 1,
  isDeleted: false,
  boundElements: null,
  updated: 1,
  link: null,
  locked: false,
});

function textElement(id, text, x, y, width, fontSize = 16, align = "center") {
  const lines = text.split("\n").length;
  return {
    ...baseElement(id),
    type: "text",
    x,
    y,
    width,
    height: Math.ceil(fontSize * 2.5 * lines),
    text,
    fontSize,
    fontFamily: 2,
    strokeColor: "#000000",
    backgroundColor: "transparent",
    fillStyle: "solid",
    strokeWidth: 1,
    roughness: 0,
    roundness: null,
    textAlign: align,
    verticalAlign: "top",
    containerId: null,
    originalText: text,
    autoResize: false,
    lineHeight: 1.25,
  };
}

function rectangleElement(item, id = item.id) {
  const colors = palette[item.color];
  return {
    ...baseElement(id),
    x: item.x,
    y: item.y,
    width: item.width,
    height: item.height,
    strokeColor: colors.stroke,
    backgroundColor: item.container ? "transparent" : colors.fill,
    fillStyle: "solid",
    strokeWidth: item.container ? 2 : 2,
    strokeStyle: item.dashedBorder ? "dashed" : "solid",
  };
}

function arrowElement(diagram, item) {
  const points = edgePoints(diagram, item);
  const start = points[0];
  const relativePoints = points.map((point) => [point.x - start.x, point.y - start.y]);
  const xs = relativePoints.map(([x]) => x);
  const ys = relativePoints.map(([, y]) => y);

  return {
    ...baseElement(item.id),
    type: "arrow",
    x: start.x,
    y: start.y,
    width: Math.max(1, Math.max(...xs) - Math.min(...xs)),
    height: Math.max(1, Math.max(...ys) - Math.min(...ys)),
    strokeColor: palette[item.color].stroke,
    backgroundColor: "transparent",
    fillStyle: "solid",
    strokeStyle: item.dashed ? "dashed" : "solid",
    roundness: null,
    points: relativePoints,
    startBinding: { elementId: item.from, focus: 0, gap: 2 },
    endBinding: { elementId: item.to, focus: 0, gap: 2 },
    startArrowhead: item.bidirectional ? "arrow" : null,
    endArrowhead: "arrow",
    elbowed: false,
  };
}

function labelElements(item) {
  if (!item.label || !item.labelBox) {
    return [];
  }
  const height = 32;
  const box = {
    id: `${item.id}-label-box`,
    x: item.labelBox.x,
    y: item.labelBox.y,
    width: item.labelBox.width,
    height,
    color: "white",
    container: false,
  };
  return [
    {
      ...rectangleElement(box),
      strokeColor: palette[item.color].stroke,
      strokeWidth: 1,
      roundness: { type: 3 },
    },
    textElement(
      `${item.id}-label`,
      item.label,
      box.x + 4,
      box.y + 5,
      box.width - 8,
      12,
    ),
  ];
}

function toExcalidraw(diagram) {
  const elements = [
    textElement("title", diagram.name, 40, 20, 1000, 30, "left"),
    textElement("subtitle", diagram.subtitle, 40, 70, 2200, 16, "left"),
  ];

  for (const item of diagram.nodes.filter((candidate) => candidate.container)) {
    elements.push(rectangleElement(item));
    elements.push(textElement(
      `${item.id}-label`,
      item.label,
      item.x + 14,
      item.y + 10,
      item.width - 28,
      17,
      "left",
    ));
  }

  for (const item of diagram.edges) {
    elements.push(arrowElement(diagram, item));
  }

  for (const item of diagram.nodes.filter((candidate) => !candidate.container)) {
    elements.push(rectangleElement(item));
    const lines = item.label.split("\n").length;
    const fontSize = 15;
    const textHeight = fontSize * 1.25 * lines;
    elements.push(textElement(
      `${item.id}-label`,
      item.label,
      item.x + 8,
      item.y + Math.max(8, (item.height - textHeight) / 2),
      item.width - 16,
      fontSize,
    ));
  }

  for (const item of diagram.edges) {
    elements.push(...labelElements(item));
  }

  return {
    type: "excalidraw",
    version: 2,
    source: "copilot-sdk",
    elements,
    appState: {
      gridSize: 20,
      viewBackgroundColor: "#ffffff",
    },
    files: {},
  };
}

function xmlEscape(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function drawioTextCell(id, value, x, y, width, height, fontSize, bold = false) {
  const style = `text;html=1;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=${fontSize};${bold ? "fontStyle=1;" : ""}`;
  return `<mxCell id="${id}" value="${xmlEscape(value)}" style="${style}" vertex="1" parent="1"><mxGeometry x="${x}" y="${y}" width="${width}" height="${height}" as="geometry"/></mxCell>`;
}

function toDrawio(diagram) {
  const cells = [
    '<mxCell id="0"/>',
    '<mxCell id="1" parent="0"/>',
    drawioTextCell("title", diagram.name, 40, 20, 1000, 45, 28, true),
    drawioTextCell("subtitle", diagram.subtitle, 40, 65, 2200, 35, 15),
  ];

  for (const item of diagram.nodes) {
    const colors = palette[item.color];
    const style = item.container
      ? `rounded=1;whiteSpace=wrap;html=1;fillColor=none;strokeColor=${colors.stroke};strokeWidth=2;verticalAlign=top;align=left;spacingTop=8;spacingLeft=10;fontStyle=1;`
      : `rounded=1;whiteSpace=wrap;html=1;fillColor=${colors.fill};strokeColor=${colors.stroke};strokeWidth=2;fontColor=#000000;${item.dashedBorder ? "dashed=1;" : ""}`;
    const label = xmlEscape(item.label).replaceAll("\n", "&lt;br&gt;");
    cells.push(
      `<mxCell id="${item.id}" value="${label}" style="${style}" vertex="1" parent="1">` +
      `<mxGeometry x="${item.x}" y="${item.y}" width="${item.width}" height="${item.height}" as="geometry"/>` +
      "</mxCell>",
    );
  }

  for (const item of diagram.edges) {
    const colors = palette[item.color];
    const style =
      "edgeStyle=orthogonalEdgeStyle;rounded=1;orthogonalLoop=1;jettySize=auto;" +
      `html=1;strokeColor=${colors.stroke};strokeWidth=2;endArrow=block;endFill=1;` +
      `${item.bidirectional ? "startArrow=block;startFill=1;" : ""}` +
      `${item.dashed ? "dashed=1;" : ""}` +
      portStyle("exit", item.fromPort) +
      portStyle("entry", item.toPort);
    const waypointXml = item.waypoints.length
      ? `<Array as="points">${item.waypoints.map((point) =>
        `<mxPoint x="${point.x}" y="${point.y}"/>`).join("")}</Array>`
      : "";
    cells.push(
      `<mxCell id="${item.id}" value="" style="${style}" edge="1" parent="1" source="${item.from}" target="${item.to}">` +
      `<mxGeometry relative="1" as="geometry">${waypointXml}</mxGeometry>` +
      "</mxCell>",
    );

    if (item.label && item.labelBox) {
      cells.push(
        `<mxCell id="${item.id}-label" value="${xmlEscape(item.label)}" ` +
        `style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=${colors.stroke};strokeWidth=1;fontSize=12;" vertex="1" parent="1">` +
        `<mxGeometry x="${item.labelBox.x}" y="${item.labelBox.y}" width="${item.labelBox.width}" height="32" as="geometry"/>` +
        "</mxCell>",
      );
    }
  }

  return `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<mxfile host="app.diagrams.net" agent="copilot-sdk" version="24.7.17">\n` +
    `  <diagram id="${diagram.name.toLowerCase().replaceAll(" ", "-")}" name="${xmlEscape(diagram.name)}">\n` +
    `    <mxGraphModel dx="${diagram.width}" dy="${diagram.height}" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="${diagram.width}" pageHeight="${diagram.height}" math="0" shadow="0">\n` +
    `      <root>${cells.join("")}</root>\n` +
    "    </mxGraphModel>\n" +
    "  </diagram>\n" +
    "</mxfile>\n";
}

function svgMultilineText(text, x, y, width, height, fontSize, anchor = "middle", bold = false) {
  const lines = text.split("\n");
  const lineHeight = fontSize * 1.25;
  const firstY = y + height / 2 - ((lines.length - 1) * lineHeight) / 2;
  const textX = anchor === "start" ? x : x + width / 2;
  return `<text x="${textX}" y="${firstY}" text-anchor="${anchor}" font-family="Arial, sans-serif" font-size="${fontSize}" ${bold ? 'font-weight="700"' : ""} fill="#000000">` +
    lines.map((line, index) =>
      `<tspan x="${textX}" dy="${index === 0 ? 0 : lineHeight}">${xmlEscape(line)}</tspan>`).join("") +
    "</text>";
}

function toSvg(diagram) {
  const markerDefs = Object.entries(palette).map(([name, colors]) =>
    `<marker id="arrow-${name}" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="${colors.stroke}"/></marker>` +
    `<marker id="arrow-start-${name}" markerWidth="10" markerHeight="10" refX="1" refY="3" orient="auto-start-reverse" markerUnits="strokeWidth"><path d="M0,0 L0,6 L9,3 z" fill="${colors.stroke}"/></marker>`
  ).join("");

  const containers = diagram.nodes.filter((item) => item.container).map((item) => {
    const colors = palette[item.color];
    return `<rect x="${item.x}" y="${item.y}" width="${item.width}" height="${item.height}" rx="12" fill="none" stroke="${colors.stroke}" stroke-width="2"/>` +
      svgMultilineText(item.label, item.x + 14, item.y + 8, item.width - 28, 30, 17, "start", true);
  }).join("");

  const edges = diagram.edges.map((item) => {
    const points = edgePoints(diagram, item).map((point) => `${point.x},${point.y}`).join(" ");
    return `<polyline points="${points}" fill="none" stroke="${palette[item.color].stroke}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" ${item.dashed ? 'stroke-dasharray="10 8"' : ""} marker-end="url(#arrow-${item.color})" ${item.bidirectional ? `marker-start="url(#arrow-start-${item.color})"` : ""}/>`;
  }).join("");

  const nodes = diagram.nodes.filter((item) => !item.container).map((item) => {
    const colors = palette[item.color];
    return `<rect x="${item.x}" y="${item.y}" width="${item.width}" height="${item.height}" rx="10" fill="${colors.fill}" stroke="${colors.stroke}" stroke-width="2" ${item.dashedBorder ? 'stroke-dasharray="8 6"' : ""}/>` +
      svgMultilineText(item.label, item.x, item.y, item.width, item.height, 15);
  }).join("");

  const labels = diagram.edges.filter((item) => item.label && item.labelBox).map((item) => {
    const box = item.labelBox;
    return `<rect x="${box.x}" y="${box.y}" width="${box.width}" height="32" rx="6" fill="#FFFFFF" stroke="${palette[item.color].stroke}" stroke-width="1"/>` +
      svgMultilineText(item.label, box.x, box.y, box.width, 32, 12);
  }).join("");

  return `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<svg xmlns="http://www.w3.org/2000/svg" width="${diagram.width}" height="${diagram.height}" viewBox="0 0 ${diagram.width} ${diagram.height}">` +
    `<defs>${markerDefs}</defs><rect width="100%" height="100%" fill="#FFFFFF"/>` +
    `<text x="40" y="52" font-family="Arial, sans-serif" font-size="30" font-weight="700">${xmlEscape(diagram.name)}</text>` +
    `<text x="40" y="92" font-family="Arial, sans-serif" font-size="16">${xmlEscape(diagram.subtitle)}</text>` +
    containers + edges + nodes + labels +
    "</svg>\n";
}

function lineIntersectsNode(start, end, item) {
  if (start.x === end.x) {
    return start.x > item.x && start.x < item.x + item.width &&
      Math.max(Math.min(start.y, end.y), item.y) < Math.min(Math.max(start.y, end.y), item.y + item.height);
  }
  if (start.y === end.y) {
    return start.y > item.y && start.y < item.y + item.height &&
      Math.max(Math.min(start.x, end.x), item.x) < Math.min(Math.max(start.x, end.x), item.x + item.width);
  }
  return false;
}

function sameNumber(left, right) {
  return Math.abs(left - right) < 0.001;
}

function pointIsEndpoint(point, start, end) {
  return (sameNumber(point.x, start.x) && sameNumber(point.y, start.y)) ||
    (sameNumber(point.x, end.x) && sameNumber(point.y, end.y));
}

function segmentConflict(a1, a2, b1, b2) {
  const aVertical = sameNumber(a1.x, a2.x);
  const aHorizontal = sameNumber(a1.y, a2.y);
  const bVertical = sameNumber(b1.x, b2.x);
  const bHorizontal = sameNumber(b1.y, b2.y);

  if ((!aVertical && !aHorizontal) || (!bVertical && !bHorizontal)) {
    return null;
  }

  if (aVertical && bVertical && sameNumber(a1.x, b1.x)) {
    const overlapStart = Math.max(Math.min(a1.y, a2.y), Math.min(b1.y, b2.y));
    const overlapEnd = Math.min(Math.max(a1.y, a2.y), Math.max(b1.y, b2.y));
    return overlapEnd - overlapStart > 0.001 ? "overlap" : null;
  }

  if (aHorizontal && bHorizontal && sameNumber(a1.y, b1.y)) {
    const overlapStart = Math.max(Math.min(a1.x, a2.x), Math.min(b1.x, b2.x));
    const overlapEnd = Math.min(Math.max(a1.x, a2.x), Math.max(b1.x, b2.x));
    return overlapEnd - overlapStart > 0.001 ? "overlap" : null;
  }

  const verticalStart = aVertical ? a1 : b1;
  const verticalEnd = aVertical ? a2 : b2;
  const horizontalStart = aHorizontal ? a1 : b1;
  const horizontalEnd = aHorizontal ? a2 : b2;
  const point = { x: verticalStart.x, y: horizontalStart.y };
  const onVertical = point.y >= Math.min(verticalStart.y, verticalEnd.y) &&
    point.y <= Math.max(verticalStart.y, verticalEnd.y);
  const onHorizontal = point.x >= Math.min(horizontalStart.x, horizontalEnd.x) &&
    point.x <= Math.max(horizontalStart.x, horizontalEnd.x);

  if (!onVertical || !onHorizontal) {
    return null;
  }

  const endpointOfA = pointIsEndpoint(point, a1, a2);
  const endpointOfB = pointIsEndpoint(point, b1, b2);
  return endpointOfA && endpointOfB ? null : "crossing";
}

function validateDiagram(diagram) {
  const ids = new Set();
  for (const item of diagram.nodes) {
    if (ids.has(item.id)) {
      throw new Error(`${diagram.name}: duplicate node ID ${item.id}`);
    }
    ids.add(item.id);
  }

  for (const item of diagram.edges) {
    if (!ids.has(item.from) || !ids.has(item.to)) {
      throw new Error(`${diagram.name}: unresolved edge ${item.id}`);
    }
    const points = edgePoints(diagram, item);
    for (let index = 0; index < points.length - 1; index += 1) {
      const start = points[index];
      const end = points[index + 1];
      if (!sameNumber(start.x, end.x) && !sameNumber(start.y, end.y)) {
        throw new Error(`${diagram.name}: edge ${item.id} contains a diagonal segment`);
      }
      for (const candidate of diagram.nodes.filter((nodeItem) =>
        !nodeItem.container && nodeItem.id !== item.from && nodeItem.id !== item.to &&
        !nodeItem.id.startsWith("legend-"))) {
        if (lineIntersectsNode(start, end, candidate)) {
          throw new Error(`${diagram.name}: edge ${item.id} crosses node ${candidate.id}`);
        }
      }
    }

    for (let leftIndex = 0; leftIndex < diagram.edges.length; leftIndex += 1) {
      const leftEdge = diagram.edges[leftIndex];
      const leftPoints = edgePoints(diagram, leftEdge);
      for (let rightIndex = leftIndex + 1; rightIndex < diagram.edges.length; rightIndex += 1) {
        const rightEdge = diagram.edges[rightIndex];
        const rightPoints = edgePoints(diagram, rightEdge);
        for (let leftSegment = 0; leftSegment < leftPoints.length - 1; leftSegment += 1) {
          for (let rightSegment = 0; rightSegment < rightPoints.length - 1; rightSegment += 1) {
            const conflict = segmentConflict(
              leftPoints[leftSegment],
              leftPoints[leftSegment + 1],
              rightPoints[rightSegment],
              rightPoints[rightSegment + 1],
            );
            if (conflict) {
              throw new Error(
                `${diagram.name}: edges ${leftEdge.id} and ${rightEdge.id} have a ${conflict}`,
              );
            }
          }
        }
      }
    }
  }
}

for (const [baseName, diagram] of [
  ["system-architecture", system],
  ["network-design", network],
]) {
  validateDiagram(diagram);
  fs.writeFileSync(
    path.join(root, `${baseName}.excalidraw`),
    `${JSON.stringify(toExcalidraw(diagram), null, 2)}\n`,
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, `${baseName}.drawio`),
    toDrawio(diagram),
    "utf8",
  );
  fs.writeFileSync(
    path.join(root, `${baseName}.editable-preview.svg`),
    toSvg(diagram),
    "utf8",
  );
}

console.log("Generated routed Excalidraw, Draw.io, and matching SVG previews.");
