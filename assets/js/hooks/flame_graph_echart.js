import * as echarts from "echarts"

// Deterministic per-name color (same function always gets the same color across the graph),
// without needing a fixed lookup table for arbitrary Elixir module/function names.
function colorFor(name) {
  let hash = 0
  for (let i = 0; i < name.length; i++) {
    hash = (hash << 5) - hash + name.charCodeAt(i)
    hash |= 0
  }
  return `hsl(${Math.abs(hash) % 360}, 65%, 60%)`
}

// The server sends a plain {name, value, children} tree (see ObserverWeb.Tracer.Tool.FlameGraph) -
// tags each node with a stable path-based id so click-to-zoom can find the clicked frame again
// after the tree gets re-rooted.
function assignIds(node, path) {
  node.id = path
  ;(node.children || []).forEach((child, index) => assignIds(child, `${path}.${index}`))
  return node
}

// Collapses everything outside the path from the root down to `id`, keeping the target frame's
// own subtree intact - the classic flame graph "zoom to frame" interaction. Returns null if `id`
// isn't found (e.g. a stale click from before new data replaced the tree).
function pruneToPath(node, id) {
  if (node.id === id) return node

  for (const child of node.children || []) {
    const pruned = pruneToPath(child, id)
    if (pruned) return { ...node, value: pruned.value, children: [pruned] }
  }

  return null
}

function maxDepth(node) {
  const children = node.children || []
  return children.length === 0 ? 0 : 1 + Math.max(...children.map(maxDepth))
}

// Flattens the tree into the [level, start, end, name, percent] rows the "custom" series below
// draws as rects, laying children out left-to-right across their parent's [start, end) span.
function flatten(root) {
  const rows = []
  const rootValue = root.value

  function walk(node, start, level) {
    rows.push({
      id: node.id,
      value: [
        level,
        start,
        start + node.value,
        node.name,
        rootValue === 0 ? 0 : (node.value / rootValue) * 100
      ],
      itemStyle: { color: colorFor(node.name) }
    })

    let childStart = start
    for (const child of node.children || []) {
      walk(child, childStart, level + 1)
      childStart += child.value
    }
  }

  walk(root, 0, 0)
  return rows
}

function renderItem(params, api) {
  const level = api.value(0)
  const start = api.coord([api.value(1), level])
  const end = api.coord([api.value(2), level])
  const height = api.size([0, 1])[1]
  const width = Math.max(end[0] - start[0], 0)

  return {
    type: "rect",
    transition: ["shape"],
    shape: { x: start[0], y: start[1] - height / 2, width, height: height - 1, r: 2 },
    style: { fill: api.visual("color") },
    emphasis: { style: { stroke: "#000" } },
    textConfig: { position: "insideLeft" },
    textContent: {
      style: {
        text: api.value(3),
        fill: "#000",
        width: width - 4,
        overflow: "truncate",
        ellipsis: ".."
      }
    }
  }
}

function buildOption(root) {
  return {
    tooltip: {
      formatter(params) {
        const [, start, end, name, percent] = params.value
        return `${params.marker} ${name}: ${(end - start).toLocaleString()}µs (${percent.toFixed(2)}%)`
      }
    },
    toolbox: {
      feature: { restore: {} },
      right: 10,
      top: 5
    },
    xAxis: { show: false, max: Math.max(root.value, 1) },
    yAxis: { show: false, max: Math.max(maxDepth(root), 1) },
    series: [
      {
        type: "custom",
        renderItem,
        encode: { x: [1, 2], y: 0 },
        data: flatten(root)
      }
    ]
  }
}

const FlameGraphEChart = {
  mounted() {
    const selector = "#" + this.el.id
    this.chart = echarts.init(this.el.querySelector(selector + "-chart"))
    this.rawData = this.el.querySelector(selector + "-data").textContent
    this.root = assignIds(JSON.parse(this.rawData), "0")
    this.chart.setOption(buildOption(this.root))

    this.chart.on("click", (params) => {
      const target = params.data && pruneToPath(this.root, params.data.id)
      if (target) this.chart.setOption(buildOption(target), true)
    })
  },
  updated() {
    const selector = "#" + this.el.id
    const rawData = this.el.querySelector(selector + "-data").textContent
    if (rawData === this.rawData) return

    this.rawData = rawData
    this.root = assignIds(JSON.parse(rawData), "0")
    this.chart.setOption(buildOption(this.root), true)
  }
}

export default FlameGraphEChart
