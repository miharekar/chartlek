import { Controller } from "@hotwired/stimulus"

const STYLES = { light: "mapbox://styles/mapbox/light-v11", dark: "mapbox://styles/mapbox/dark-v11" }
const PADDING = 32
const HILLSHADE = {
  light: { shadow: "#52525b", highlight: "#ffffff", accent: "#a1a1aa", exaggeration: 0.3 },
  dark: { shadow: "#000000", highlight: "#71717a", accent: "#18181b", exaggeration: 0.4 }
}
const BELOW_ROADS = /^(land-structure|aeroway|building|tunnel|road|bridge)/
const ROADS = /^(tunnel|road|bridge)/
const INDEX_CONTOUR = [">=", ["get", "index"], 5]
const TEXT_FONT = ["DIN Pro Medium", "Arial Unicode MS Regular"]

const color = name => getComputedStyle(document.documentElement).getPropertyValue(name).trim()

export default class extends Controller {
  static values = { route: Array, token: String }

  async connect() {
    const connection = (this.connection = Symbol())
    await import("mapbox-gl")
    if (this.connection !== connection) return

    const { mapboxgl } = window
    mapboxgl.accessToken = this.tokenValue
    this.scheme = matchMedia("(prefers-color-scheme: dark)")
    this.map = new mapboxgl.Map({ container: this.element, style: this.#style(), scrollZoom: false, performanceMetricsCollection: false, bounds: this.#bounds(), fitBoundsOptions: { padding: PADDING } })
    this.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right")
    this.map.on("style.load", () => this.#draw())
    this.changeScheme = () => {
      if (this.#following()) this.map.setStyle(this.#style(), { diff: false })
    }
    this.scheme.addEventListener("change", this.changeScheme)
  }

  disconnect() {
    this.connection = null
    this.scheme?.removeEventListener("change", this.changeScheme)
    this.map?.remove()
    this.map = this.scheme = null
  }

  #dark() {
    const theme = document.documentElement.dataset.theme
    return theme === "dark" || (this.#following() && this.scheme.matches)
  }

  #style() {
    return this.#dark() ? STYLES.dark : STYLES.light
  }

  #following() {
    return !["light", "dark"].includes(document.documentElement.dataset.theme)
  }

  #bounds() {
    const longitudes = this.routeValue.map(([longitude]) => longitude)
    const latitudes = this.routeValue.map(([, latitude]) => latitude)
    return [[Math.min(...longitudes), Math.min(...latitudes)], [Math.max(...longitudes), Math.max(...latitudes)]]
  }

  #drawTerrain() {
    const layers = this.map.getStyle().layers
    const firstLayer = pattern => layers.find(layer => pattern.test(layer.id))?.id
    const labels = layers.find(layer => layer.type === "symbol")?.id
    const shading = this.#dark() ? HILLSHADE.dark : HILLSHADE.light
    const halo = { "text-halo-color": color("--chart-grid"), "text-halo-width": 1.2 }
    const contour = { source: "composite", "source-layer": "contour" }

    this.map.addSource("terrain-dem", { type: "raster-dem", url: "mapbox://mapbox.mapbox-terrain-dem-v1", tileSize: 512, maxzoom: 14 })
    this.map.addLayer({ id: "hillshade", type: "hillshade", source: "terrain-dem", paint: { "hillshade-exaggeration": shading.exaggeration, "hillshade-shadow-color": shading.shadow, "hillshade-highlight-color": shading.highlight, "hillshade-accent-color": shading.accent } }, firstLayer(BELOW_ROADS))
    this.map.addLayer({ id: "contours-minor", type: "line", ...contour, minzoom: 13, filter: ["<", ["get", "index"], 5], paint: { "line-color": color("--chart-muted"), "line-width": 0.5, "line-opacity": 0.3 } }, firstLayer(ROADS))
    this.map.addLayer({ id: "contours-index", type: "line", ...contour, minzoom: 11, filter: INDEX_CONTOUR, paint: { "line-color": color("--chart-muted"), "line-width": ["interpolate", ["linear"], ["zoom"], 11, 0.5, 15, 0.9], "line-opacity": 0.5 } }, firstLayer(ROADS))
    this.map.addLayer({ id: "contour-labels", type: "symbol", ...contour, minzoom: 11, filter: INDEX_CONTOUR, layout: { "symbol-placement": "line", "symbol-spacing": 250, "text-field": ["concat", ["to-string", ["get", "ele"]], " m"], "text-font": TEXT_FONT, "text-size": 10 }, paint: { "text-color": color("--chart-axis"), ...halo } }, labels)
    this.map.addLayer({
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

  #draw() {
    this.#drawTerrain()
    const route = this.routeValue
    const point = (coordinates, kind) => ({ type: "Feature", properties: { kind }, geometry: { type: "Point", coordinates } })

    this.map.addSource("route", { type: "geojson", data: { type: "Feature", geometry: { type: "LineString", coordinates: route } } })
    this.map.addSource("ends", { type: "geojson", data: { type: "FeatureCollection", features: [point(route[0], "start"), point(route.at(-1), "end")] } })
    this.map.addLayer({ id: "route", type: "line", source: "route", layout: { "line-join": "round", "line-cap": "round" }, paint: { "line-color": color("--chart-accent"), "line-width": 4 } })
    const marker = (kind, radius, fill) => ({ id: kind, type: "circle", source: "ends", filter: ["==", ["get", "kind"], kind], paint: { "circle-radius": radius, "circle-color": fill, "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } })
    this.map.addLayer(marker("end", 9, color("--chart-highlight")))
    this.map.addLayer(marker("start", 5, color("--chart-accent-highlight")))
  }
}
