const STYLES = { light: "mapbox://styles/mapbox/light-v11", dark: "mapbox://styles/mapbox/dark-v11" }
const HILLSHADE = {
  light: { shadow: "#52525b", highlight: "#ffffff", accent: "#a1a1aa", exaggeration: 0.3 },
  dark: { shadow: "#000000", highlight: "#71717a", accent: "#18181b", exaggeration: 0.4 }
}
const BELOW_ROADS = /^(land-structure|aeroway|building|tunnel|road|bridge)/
const ROADS = /^(tunnel|road|bridge)/
const INDEX_CONTOUR = [">=", ["get", "index"], 5]
const TEXT_FONT = ["DIN Pro Medium", "Arial Unicode MS Regular"]

export const color = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

export function following() {
  return !["light", "dark"].includes(document.documentElement.dataset.theme)
}

export function isDark(scheme) {
  return document.documentElement.dataset.theme === "dark" || (following() && scheme.matches)
}

export function styleUrl(scheme) {
  return isDark(scheme) ? STYLES.dark : STYLES.light
}

export function drawTerrain(map, dark) {
  const layers = map.getStyle().layers
  const firstLayer = pattern => layers.find(layer => pattern.test(layer.id))?.id
  const labels = layers.find(layer => layer.type === "symbol")?.id
  const shading = dark ? HILLSHADE.dark : HILLSHADE.light
  const halo = { "text-halo-color": color("--chart-grid"), "text-halo-width": 1.2 }
  const contour = { source: "composite", "source-layer": "contour" }

  map.addSource("terrain-dem", { type: "raster-dem", url: "mapbox://mapbox.mapbox-terrain-dem-v1", tileSize: 512, maxzoom: 14 })
  map.addLayer({ id: "hillshade", type: "hillshade", source: "terrain-dem", paint: { "hillshade-exaggeration": shading.exaggeration, "hillshade-shadow-color": shading.shadow, "hillshade-highlight-color": shading.highlight, "hillshade-accent-color": shading.accent } }, firstLayer(BELOW_ROADS))
  map.addLayer({ id: "contours-minor", type: "line", ...contour, minzoom: 13, filter: ["<", ["get", "index"], 5], paint: { "line-color": color("--chart-muted"), "line-width": 0.5, "line-opacity": 0.3 } }, firstLayer(ROADS))
  map.addLayer({ id: "contours-index", type: "line", ...contour, minzoom: 11, filter: INDEX_CONTOUR, paint: { "line-color": color("--chart-muted"), "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.5, 15, 0.9], "line-opacity": 0.5 } }, firstLayer(ROADS))
  map.addLayer({ id: "contour-labels", type: "symbol", ...contour, minzoom: 11, filter: INDEX_CONTOUR, layout: { "symbol-placement": "line", "symbol-spacing": 250, "text-field": ["concat", ["to-string", ["get", "ele"]], " m"], "text-font": TEXT_FONT, "text-size": 10 }, paint: { "text-color": color("--chart-axis"), ...halo } }, labels)
  map.addLayer({
    id: "peaks",
    type: "symbol",
    source: "composite",
    "source-layer": "natural_label",
    minzoom: 9,
    filter: ["all", ["==", ["geometry-type"], "Point"], ["match", ["get", "maki"], ["mountain", "volcano"], true, false]],
    layout: {
      "text-field": ["format", "▲", { "font-scale": 1.1 }, "\n", {}, ["coalesce", ["get", "name_en"], ["get", "name"], ""], {}, ["case", ["has", "elevation_m"], ["concat", "\n", ["to-string", ["get", "elevation_m"]], " m"], ""], { "font-scale": 0.85 }],
      "text-font": TEXT_FONT,
      "text-size": 11,
      "text-max-width": 8,
      "text-padding": 8,
      "symbol-sort-key": ["-", ["coalesce", ["get", "elevation_m"], 0]]
    },
    paint: { "text-color": color("--chart-axis"), ...halo }
  }, labels)
}

let swatch

export function resolveColor(name) {
  const context = (swatch ??= document.createElement("canvas").getContext("2d", { willReadFrequently: true }))
  context.fillStyle = color(name)
  context.fillRect(0, 0, 1, 1)
  const [red, green, blue] = context.getImageData(0, 0, 1, 1).data
  return `rgb(${red}, ${green}, ${blue})`
}
