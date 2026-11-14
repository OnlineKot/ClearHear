import SwiftUI
import CoreLocation

struct LocationView: View {
    @EnvironmentObject private var loc: LocationHub
    @State private var copied = false
    @State private var spotName = "Moje miejsce"

    private var place: String {
        guard let p = loc.placemark else { return loc.location == nil ? "Szukam…" : "Nieznane miejsce" }
        return p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? p.country ?? "Nieznane miejsce"
    }

    private var address: String {
        guard let p = loc.placemark else { return "" }
        var parts: [String] = []
        if let s = p.thoroughfare { parts.append(s + (p.subThoroughfare.map { " " + $0 } ?? "")) }
        if let z = p.postalCode { parts.append(z) }
        if let c = p.country { parts.append(c) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Page("Gdzie jestem", "Miejsce, kierunek, wysokość i droga z powrotem") {
            VStack(spacing: 16) {
                if loc.status == .denied || loc.status == .restricted {
                    denied
                } else if !loc.authorized && loc.status == .notDetermined {
                    Card { Text("Pozwól na lokalizację, gdy iPhone zapyta.").spaced(.subheadline, .semibold) }
                }
                hero
                compass
                stats
                spot
            }
        }
        .onAppear { loc.start() }
        .onDisappear { loc.stop() }
    }

    private var denied: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Brak dostępu do lokalizacji", systemImage: "location.slash.fill").spaced(.headline, .bold)
                Text("Włącz ją w Ustawieniach telefonu. W LiveContainerze zgoda dotyczy samego LiveContainera.")
                    .spaced(.footnote).foregroundStyle(.secondary)
                Button("Otwórz Ustawienia") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var hero: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(place).spaced(.largeTitle, .bold).contentTransition(.interpolate)
                if !address.isEmpty { Text(address).spaced(.subheadline).foregroundStyle(.secondary) }
                if let l = loc.location {
                    let lat = l.coordinate.latitude, lon = l.coordinate.longitude
                    Text(String(format: "%.5f, %.5f", lat, lon)).spaced(.headline).monospacedDigit()
                    Text(Geo.dms(lat, positive: "N", negative: "S") + "  " + Geo.dms(lon, positive: "E", negative: "W"))
                        .spaced(.footnote).foregroundStyle(.secondary).monospacedDigit()
                    HStack(spacing: 10) {
                        Button {
                            UIPasteboard.general.string = String(format: "%.6f, %.6f", lat, lon)
                            copied = true
                            Haptics.ok()
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        } label: {
                            Chip(text: copied ? "Skopiowano" : "Kopiuj", symbol: copied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=Jestem+tutaj") {
                            ShareLink(item: url) { Chip(text: "Wyślij", symbol: "square.and.arrow.up") }.buttonStyle(.plain)
                            Link(destination: url) { Chip(text: "Mapy", symbol: "map.fill") }
                        }
                    }
                }
            }
        }
    }

    private var compass: some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                    ForEach(0..<4, id: \.self) { i in
                        Text(["N", "E", "S", "W"][i])
                            .spaced(.caption, .bold)
                            .foregroundStyle(i == 0 ? Color.red : .white)
                            .offset(y: -50)
                            .rotationEffect(.degrees(Double(i) * 90))
                    }
                    .rotationEffect(.degrees(-(loc.heading ?? 0)))
                    .animation(.smooth(duration: 0.25), value: loc.heading)
                    Image(systemName: "location.north.fill").font(.system(size: 26)).foregroundStyle(Theme.gold)
                }
                .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.heading.map { String(format: "%.0f°", $0) } ?? "–").font(.system(size: 40, weight: .bold, design: .rounded))
                    Text(loc.heading.map { Geo.compassName($0) } ?? "Kompas niedostępny")
                        .spaced(.headline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var stats: some View {
        let l = loc.location
        let tz = TimeZone.current
        let off = tz.secondsFromGMT() / 60
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        var sunText = "–"
        if let l, let t = Sun.times(dayOfYear: day, lat: l.coordinate.latitude, lon: l.coordinate.longitude) {
            sunText = "↑ \(Sun.hhmm(t.rise, utcOffsetMinutes: off))  ↓ \(Sun.hhmm(t.set, utcOffsetMinutes: off))"
        } else if l != nil {
            sunText = "doba polarna"
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            stat("Wysokość", l.map { String(format: "%.0f m", $0.altitude) } ?? "–", "mountain.2.fill")
            stat("Prędkość", l.map { $0.speed >= 0 ? String(format: "%.0f km/h", $0.speed * 3.6) : "0 km/h" } ?? "–", "speedometer")
            stat("Dokładność", l.map { String(format: "± %.0f m", $0.horizontalAccuracy) } ?? "–", "scope")
            stat("Strefa czasu", tz.identifier.replacingOccurrences(of: "_", with: " "), "clock.fill")
            stat("Słońce", sunText, "sun.max.fill")
            stat("Ciśnienie", loc.pressure.map { String(format: "%.0f hPa", $0 * 10) } ?? "brak barometru", "barometer")
        }
    }

    private func stat(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.gold)
            Text(value).spaced(.headline, .bold).minimumScaleFactor(0.7).lineLimit(2)
            Text(title).spaced(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    // zapamietane miejsce (parking) i droga do niego
    private var spot: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Zapamiętane miejsce", systemImage: "parkingsign.circle.fill").spaced(.headline, .bold)
                if let s = loc.saved {
                    let here = loc.location
                    let dist = here.map { Geo.distance($0.coordinate.latitude, $0.coordinate.longitude, s.lat, s.lon) }
                    let brg = here.map { Geo.bearing($0.coordinate.latitude, $0.coordinate.longitude, s.lat, s.lon) }
                    HStack(spacing: 18) {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(Theme.gold)
                            .rotationEffect(.degrees((brg ?? 0) - (loc.heading ?? 0)))
                            .animation(.smooth(duration: 0.3), value: loc.heading)
                            .frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dist.map { Geo.distanceText($0) } ?? "–").font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("\(s.name), zapisane \(s.date.formatted(date: .omitted, time: .shortened))")
                                .spaced(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        if let url = URL(string: "https://maps.apple.com/?daddr=\(s.lat),\(s.lon)&dirflg=w") {
                            Link(destination: url) { Chip(text: "Prowadź", symbol: "figure.walk") }
                        }
                        Button { loc.forget() } label: { Chip(text: "Usuń", symbol: "trash") }.buttonStyle(.plain)
                    }
                } else {
                    TextField("Nazwa", text: $spotName)
                        .padding(12).glassEffect(.regular, in: .capsule)
                    Button {
                        loc.saveHere(name: spotName)
                        Haptics.ok()
                    } label: {
                        Label("Zapamiętaj, gdzie jestem", systemImage: "mappin.and.ellipse")
                            .spaced(.subheadline, .bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.gold)
                    .disabled(loc.location == nil)
                    Text("Zaparkuj, zapisz miejsce i wróć do niego strzałką, nawet bez internetu.")
                        .spaced(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}
