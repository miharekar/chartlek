import { Controller } from "@hotwired/stimulus"

const STYLES = { light: "mapbox://styles/mapbox/light-v11", dark: "mapbox://styles/mapbox/dark-v11" }
const PADDING = 32

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
    this.changeScheme = () => this.map.setStyle(this.#style(), { diff: false })
    this.scheme.addEventListener("change", this.changeScheme)
  }

  disconnect() {
    this.connection = null
    this.scheme?.removeEventListener("change", this.changeScheme)
    this.map?.remove()
    this.map = this.scheme = null
  }

  #style() {
    return this.scheme.matches ? STYLES.dark : STYLES.light
  }

  #bounds() {
    const longitudes = this.routeValue.map(([longitude]) => longitude)
    const latitudes = this.routeValue.map(([, latitude]) => latitude)
    return [[Math.min(...longitudes), Math.min(...latitudes)], [Math.max(...longitudes), Math.max(...latitudes)]]
  }

  #draw() {
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
