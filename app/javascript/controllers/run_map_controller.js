import { Controller } from "@hotwired/stimulus"
import { routeAt } from "helpers/route_point"
import { color, drawTerrain, following, isDark, styleUrl } from "helpers/map_base"
import { subscribe } from "helpers/run_cursor"

const PADDING = 32

export default class extends Controller {
  static values = { route: Array, distances: Array, token: String }

  async connect() {
    this.unsubscribe = subscribe(distance => {
      this.cursor = distance
      this.#showCursor()
    })
    const connection = (this.connection = Symbol())
    await import("mapbox-gl")
    if (this.connection !== connection) return

    const { mapboxgl } = window
    mapboxgl.accessToken = this.tokenValue
    this.scheme = matchMedia("(prefers-color-scheme: dark)")
    this.map = new mapboxgl.Map({ container: this.element, style: styleUrl(this.scheme), scrollZoom: false, performanceMetricsCollection: false, bounds: this.#bounds(), fitBoundsOptions: { padding: PADDING } })
    this.map.addControl(new mapboxgl.NavigationControl({ showCompass: false }), "top-right")
    this.map.on("style.load", () => this.#draw())
    this.changeScheme = () => {
      if (following()) this.map.setStyle(styleUrl(this.scheme), { diff: false })
    }
    this.scheme.addEventListener("change", this.changeScheme)
  }

  disconnect() {
    this.unsubscribe()
    this.connection = null
    this.scheme?.removeEventListener("change", this.changeScheme)
    this.map?.remove()
    this.map = this.scheme = null
  }

  #bounds() {
    const longitudes = this.routeValue.map(([longitude]) => longitude)
    const latitudes = this.routeValue.map(([, latitude]) => latitude)
    return [[Math.min(...longitudes), Math.min(...latitudes)], [Math.max(...longitudes), Math.max(...latitudes)]]
  }

  #draw() {
    drawTerrain(this.map, isDark(this.scheme))
    const route = this.routeValue
    const point = (coordinates, kind) => ({ type: "Feature", properties: { kind }, geometry: { type: "Point", coordinates } })

    this.map.addSource("route", { type: "geojson", data: { type: "Feature", geometry: { type: "LineString", coordinates: route } } })
    this.map.addSource("ends", { type: "geojson", data: { type: "FeatureCollection", features: [point(route[0], "start"), point(route.at(-1), "end")] } })
    this.map.addLayer({ id: "route", type: "line", source: "route", layout: { "line-join": "round", "line-cap": "round" }, paint: { "line-color": color("--chart-accent"), "line-width": 4 } })
    const marker = (kind, radius, fill) => ({ id: kind, type: "circle", source: "ends", filter: ["==", ["get", "kind"], kind], paint: { "circle-radius": radius, "circle-color": fill, "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } })
    this.map.addLayer(marker("end", 9, color("--chart-highlight")))
    this.map.addLayer(marker("start", 5, color("--chart-accent-highlight")))
    this.map.addSource("cursor", { type: "geojson", data: this.#cursorData() })
    this.map.addLayer({ id: "cursor-halo", type: "circle", source: "cursor", paint: { "circle-radius": 13, "circle-color": color("--chart-highlight"), "circle-opacity": 0.35 } })
    this.map.addLayer({ id: "cursor", type: "circle", source: "cursor", paint: { "circle-radius": 6, "circle-color": color("--chart-highlight"), "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } })
  }

  #cursorData() {
    const point = this.cursor == null ? null : routeAt(this.routeValue, this.distancesValue, this.cursor)
    return { type: "FeatureCollection", features: point ? [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: point } }] : [] }
  }

  #showCursor() {
    this.map?.getSource("cursor")?.setData(this.#cursorData())
  }
}
