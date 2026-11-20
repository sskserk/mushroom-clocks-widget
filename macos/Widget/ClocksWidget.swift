import SwiftUI
import WidgetKit

struct ClocksEntry: TimelineEntry {
    let date: Date
    let cities: [ClockCity]
    let settings: ClockSettings
    /// False for the reserve entries far ahead, which are drawn more cheaply
    /// (see ClocksProvider.getTimeline).
    var detailed = true
}

/// Reads the city list and settings the app saved (see CityStore). The app
/// asks WidgetKit to reload whenever either changes.
struct ClocksProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClocksEntry {
        ClocksEntry(date: .now, cities: CityStore.load(), settings: ClockSettings.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ClocksEntry) -> Void) {
        completion(ClocksEntry(date: .now, cities: CityStore.load(), settings: ClockSettings.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClocksEntry>) -> Void) {
        // The digits tick on their own, so an entry is only needed when a label
        // or icon changes (see ClockText.timelineDates).
        //
        // The timeline is rebuilt twice a day but reaches days ahead. The
        // system rebuilds it when it sees fit, and not while the Mac sleeps;
        // if the entries ran out first (over a weekend, say) the widget would
        // be left on the last one, with a stale date and stopped clocks.
        //
        // How far ahead is limited by the archive the system keeps of the
        // timeline: somewhere between 5 and 10 MB it rejects the timeline and
        // the widget goes blank. So the entries past the first day are fewer
        // and without the blinking colon, and the timeline stops where the
        // estimated archive reaches archiveBudget.
        let cities = CityStore.load()
        let settings = ClockSettings.load()
        let now = Date()
        let layout = ClocksWidgetView.layout(family: context.family, cityCount: cities.count)
        let shown = Array(cities.prefix(layout.limit))
        var entries: [ClocksEntry] = []
        var size = 0
        for date in ClockText.timelineDates(from: now, zones: Set(cities.map(\.timeZone) + [TimeZone.current]), days: 6) {
            let detailed = date <= now.addingTimeInterval(ClockText.detailedSpan)
            size += Self.archiveSize(of: shown, at: date, settings: settings, detailed: detailed, size: layout.size)
            if size > Self.archiveBudget && !entries.isEmpty { break }
            entries.append(ClocksEntry(date: date, cities: cities, settings: settings, detailed: detailed))
        }
        let reload = min(now.addingTimeInterval(12 * 3600), entries.last?.date ?? now)
        completion(Timeline(entries: entries, policy: .after(reload)))
    }

    /// For the estimates of archiveSize, which run about a quarter high: the
    /// timelines this allows came out at 5.4 to 5.6 MB and were accepted.
    /// The smallest one seen rejected was 10.6 MB.
    static let archiveBudget = 7_000_000

    /// Roughly the bytes one entry adds to the timeline archive. Measured on
    /// macOS 26: about 14 kB for every ticking text, of which a city has one
    /// (two with seconds) and a blinking colon ten, and about 25 kB for the
    /// rest of a city's row. Those figures are for the compact text; the
    /// larger text costs more (see sizeFactor).
    static func archiveSize(of cities: [ClockCity], at date: Date, settings: ClockSettings, detailed: Bool,
                            size: ClocksView.Size) -> Int {
        let blinking = detailed && !settings.showSeconds ? cities.filter { ClockText.isHome($0.timeZone, at: date) }.count : 0
        let timers = cities.count * (settings.showSeconds ? 2 : 1) + blinking * 10
        let compact = 10_000 + cities.count * 25_000 + timers * 14_500
        return Int(Double(compact) * sizeFactor[size]!)
    }

    /// How much more an entry costs at each text size than at compact. The
    /// archive grows with the size of the ticking text, and the blinking
    /// colon's peepholes are set in a font that grows with it. Wide is
    /// measured: with three cities the same timeline came out at 5.3 MB in a
    /// small widget and 10.7 MB (rejected) in a medium one. Roomy is not yet
    /// measured; its value assumes growth with the 1.5th power of the time's
    /// font size (17, 27, 34 pt), which fits the wide measurement.
    static let sizeFactor: [ClocksView.Size: Double] = [.compact: 1, .wide: 2.05, .roomy: 2.9]
}

struct ClocksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: ClocksEntry

    /// Columns, maximum cities and text size per widget size. Medium and large
    /// use one full-width column with big text while the cities fit, and fall
    /// back to two compact columns above that.
    static func layout(family: WidgetFamily, cityCount: Int) -> (columns: Int, limit: Int, size: ClocksView.Size) {
        switch family {
        case .systemMedium: cityCount <= 4 ? (1, 4, .wide) : (2, 8, .compact)
        case .systemLarge: cityCount <= 5 ? (1, 5, .roomy) : (2, 10, .compact)
        default: (1, 4, .compact)
        }
    }

    private var layout: (columns: Int, limit: Int, size: ClocksView.Size) {
        Self.layout(family: family, cityCount: entry.cities.count)
    }

    var body: some View {
        ClocksView(
            date: entry.date,
            cities: Array(entry.cities.prefix(layout.limit)),
            columns: layout.columns,
            size: layout.size,
            showIcons: entry.settings.showIcons,
            showSeconds: entry.settings.showSeconds,
            blinks: entry.detailed
        )
        .padding(.horizontal, layout.size == .compact ? 14 : 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The grey background for the faded look, where the one below is
            // stripped (see ClockPalette.backgroundImage).
            if renderingMode != .fullColor, let image = ClockPalette.backgroundImage {
                Image(decorative: image, scale: 1).resizable().fullColorWhenFaded()
            }
        }
        .containerBackground(for: .widget) { ClockPalette.background }
    }
}

@main
struct ClocksWidget: Widget {
    var body: some WidgetConfiguration {
        // Do not rename `kind`: macOS ties placed widgets to it.
        StaticConfiguration(kind: "Clocks", provider: ClocksProvider()) { entry in
            ClocksWidgetView(entry: entry)
        }
        .configurationDisplayName("Mushroom Clocks")
        .description("Digital clocks with each city's time difference from this Mac. Choose the cities in the Mushroom Clocks app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
