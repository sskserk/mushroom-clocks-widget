import SwiftUI
import WidgetKit

@main
struct MushroomClocksApp: App {
    var body: some Scene {
        WindowGroup {
            CityEditor()
        }
        .windowResizability(.contentSize)
    }
}

/// Pick, order and remove the cities every Mushroom Clocks widget shows, and
/// set its display options.
struct CityEditor: View {
    @State private var cities = CityStore.load()
    @State private var settings = ClockSettings.load()
    @State private var query = ""
    @State private var saveError: String?

    private var results: [ClockCity] {
        CityCatalog.search(query).filter { !cities.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Mirrors the medium widget (see ClocksWidgetView.layout).
            ClocksView(date: .now, cities: Array(cities.prefix(8)),
                       columns: cities.count <= 4 ? 1 : 2, size: cities.count <= 4 ? .wide : .compact,
                       showIcons: settings.showIcons,
                       showSeconds: settings.showSeconds)
                .padding(.horizontal, cities.count <= 4 ? 18 : 14)
                .padding(.vertical, 6)
                .frame(width: 344, height: 164)
                .background(ClockPalette.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(maxWidth: .infinity)

            HStack(alignment: .top, spacing: 16) {
                chosenList.frame(width: 280)
                catalogList.frame(width: 280)
            }
            .frame(height: 300)

            Toggle("Show country flags", isOn: $settings.showIcons)
            Toggle("Show seconds", isOn: $settings.showSeconds)

            if let saveError {
                Text("Could not save: \(saveError)").foregroundStyle(.red)
            }
            Text("Changes reach the widgets on your desktop right away. To add a widget, right-click the desktop, choose **Edit Widgets…** and search for **Mushroom Clocks**.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 616)
        .onChange(of: cities) { _, _ in save() }
        .onChange(of: settings) { _, _ in save() }
        .onAppear { save() }
    }

    private var chosenList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your cities (\(cities.count) of \(CityStore.maxCities))").font(.headline)
            List {
                ForEach(cities) { city in
                    HStack {
                        Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                        Text(city.name)
                        Spacer()
                        Text(ClockText.offset(of: city.timeZone, at: .now)).foregroundStyle(.secondary)
                        Button {
                            cities.removeAll { $0 == city }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(cities.count == 1)
                        .help("Remove \(city.name)")
                    }
                }
                .onMove { cities.move(fromOffsets: $0, toOffset: $1) }
            }
            Text("Drag to reorder. Small shows the first 4, medium 8, large all 10.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var catalogList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add a city").font(.headline)
            TextField("Search cities", text: $query).textFieldStyle(.roundedBorder)
            List(results.prefix(200)) { city in
                Button {
                    cities.append(city)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                        Text(city.name)
                        Spacer()
                        Text(ClockText.offset(of: city.timeZone, at: .now)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(cities.count >= CityStore.maxCities)
            }
        }
    }

    private func save() {
        do {
            try CityStore.save(cities)
            try settings.save()
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
