import Foundation

/// One clock: a display name and its time zone identifier.
struct ClockCity: Identifiable, Hashable, Codable {
    var name: String
    var zone: String

    var id: String { "\(zone)|\(name)" }
    var timeZone: TimeZone { TimeZone(identifier: zone) ?? .current }
    /// The language of the city's country, used for its date.
    var locale: Locale { ZoneRegions.locale(forZone: zone) }
}

/// The chosen cities: written by the app, read by the widget.
///
/// Cities are deliberately NOT a widget-editor (App Intent) setting. This app is
/// signed without a developer certificate, and macOS then refuses to decode
/// intent parameters for it, so every editor choice reaches the widget as nil.
/// A JSON file that the sandboxed widget may read through a read-only
/// entitlement has no such dependency.
enum CityStore {
    static let maxCities = 10

    /// ~/Library/Application Support/MushroomClocks in the real home folder.
    /// (NSHomeDirectory() inside the widget points at its sandbox container.)
    static var directory: URL {
        let home = getpwuid(getuid()).flatMap { $0.pointee.pw_dir }.map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/MushroomClocks")
    }

    static var fileURL: URL { directory.appendingPathComponent("cities.json") }

    static func load() -> [ClockCity] {
        guard let data = try? Data(contentsOf: fileURL),
              let cities = try? JSONDecoder().decode([ClockCity].self, from: data),
              !cities.isEmpty else { return defaults }
        return Array(cities.prefix(maxCities))
    }

    static func save(_ cities: [ClockCity]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try encoder.encode(Array(cities.prefix(maxCities))).write(to: fileURL, options: .atomic)
    }

    /// Used until a list is saved: this Mac's zone plus three far-apart cities.
    static var defaults: [ClockCity] {
        let local = TimeZone.current.identifier
        let others = [("London", "Europe/London"), ("New York", "America/New_York"), ("Tokyo", "Asia/Tokyo")]
            .filter { $0.1 != local }
            .map { ClockCity(name: $0.0, zone: $0.1) }
        return [ClockCity(name: CityCatalog.cityName(fromZone: local), zone: local)] + others
    }
}

/// Display options: like the cities, written by the app and read by the widget
/// from a JSON file next to cities.json (see CityStore for why).
struct ClockSettings: Codable, Equatable {
    /// The country flag to the right of each time.
    var showIcons = true
    /// Small ticking seconds after each time, in place of the blinking colon.
    var showSeconds = false

    init() {}

    /// Settings saved before an option existed keep that option's default.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showIcons = try values.decodeIfPresent(Bool.self, forKey: .showIcons) ?? true
        showSeconds = try values.decodeIfPresent(Bool.self, forKey: .showSeconds) ?? false
    }

    static var fileURL: URL { CityStore.directory.appendingPathComponent("settings.json") }

    static func load() -> ClockSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(ClockSettings.self, from: data) else { return ClockSettings() }
        return settings
    }

    func save() throws {
        try FileManager.default.createDirectory(at: CityStore.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.fileURL, options: .atomic)
    }
}

/// Every city the app's search offers.
enum CityCatalog {
    static func cityName(fromZone identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Curated names plus every city in the system time zone database, A to Z.
    static let all: [ClockCity] = {
        let curated = curatedList.split(separator: "\n").compactMap { line -> ClockCity? in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "|").map(String.init)
            return parts.count == 2 ? ClockCity(name: parts[0], zone: parts[1]) : nil
        }
        var seen = Set(curated.map { $0.name.lowercased() })
        let fromSystem = TimeZone.knownTimeZoneIdentifiers
            .filter { $0.contains("/") }
            .map { ClockCity(name: cityName(fromZone: $0), zone: $0) }
            .filter { seen.insert($0.name.lowercased()).inserted }
        return (curated + fromSystem).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// Matches whose name starts with the text come first.
    static func search(_ text: String) -> [ClockCity] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        let matches = all.filter { $0.name.lowercased().contains(needle) }
        return matches.filter { $0.name.lowercased().hasPrefix(needle) }
            + matches.filter { !$0.name.lowercased().hasPrefix(needle) }
    }

    /// "Name|time zone". Includes well-known cities that share another city's zone.
    private static let curatedList = """
        Abu Dhabi|Asia/Dubai
        Accra|Africa/Accra
        Addis Ababa|Africa/Addis_Ababa
        Adelaide|Australia/Adelaide
        Algiers|Africa/Algiers
        Almaty|Asia/Almaty
        Amman|Asia/Amman
        Amsterdam|Europe/Amsterdam
        Anchorage|America/Anchorage
        Ankara|Europe/Istanbul
        Astana|Asia/Almaty
        Athens|Europe/Athens
        Atlanta|America/New_York
        Auckland|Pacific/Auckland
        Austin|America/Chicago
        Baghdad|Asia/Baghdad
        Baku|Asia/Baku
        Bangkok|Asia/Bangkok
        Barcelona|Europe/Madrid
        Beijing|Asia/Shanghai
        Beirut|Asia/Beirut
        Belgrade|Europe/Belgrade
        Bengaluru|Asia/Kolkata
        Berlin|Europe/Berlin
        Bishkek|Asia/Bishkek
        Bogotá|America/Bogota
        Boston|America/New_York
        Brisbane|Australia/Brisbane
        Brussels|Europe/Brussels
        Bucharest|Europe/Bucharest
        Budapest|Europe/Budapest
        Buenos Aires|America/Argentina/Buenos_Aires
        Busan|Asia/Seoul
        Cairo|Africa/Cairo
        Calgary|America/Edmonton
        Cape Town|Africa/Johannesburg
        Caracas|America/Caracas
        Casablanca|Africa/Casablanca
        Chennai|Asia/Kolkata
        Chicago|America/Chicago
        Colombo|Asia/Colombo
        Copenhagen|Europe/Copenhagen
        Dallas|America/Chicago
        Delhi|Asia/Kolkata
        Denver|America/Denver
        Dhaka|Asia/Dhaka
        Doha|Asia/Qatar
        Dubai|Asia/Dubai
        Dublin|Europe/Dublin
        Edinburgh|Europe/London
        Frankfurt|Europe/Berlin
        Geneva|Europe/Zurich
        Guangzhou|Asia/Shanghai
        Hanoi|Asia/Ho_Chi_Minh
        Havana|America/Havana
        Helsinki|Europe/Helsinki
        Ho Chi Minh City|Asia/Ho_Chi_Minh
        Hong Kong|Asia/Hong_Kong
        Honolulu|Pacific/Honolulu
        Houston|America/Chicago
        Hyderabad|Asia/Kolkata
        Islamabad|Asia/Karachi
        Istanbul|Europe/Istanbul
        Jakarta|Asia/Jakarta
        Jerusalem|Asia/Jerusalem
        Johannesburg|Africa/Johannesburg
        Kabul|Asia/Kabul
        Karachi|Asia/Karachi
        Kathmandu|Asia/Kathmandu
        Kraków|Europe/Warsaw
        Kuala Lumpur|Asia/Kuala_Lumpur
        Kuwait City|Asia/Kuwait
        Kyiv|Europe/Kyiv
        Lagos|Africa/Lagos
        Las Vegas|America/Los_Angeles
        Lima|America/Lima
        Lisbon|Europe/Lisbon
        London|Europe/London
        Los Angeles|America/Los_Angeles
        Luxembourg|Europe/Luxembourg
        Madrid|Europe/Madrid
        Manila|Asia/Manila
        Melbourne|Australia/Melbourne
        Mexico City|America/Mexico_City
        Miami|America/New_York
        Milan|Europe/Rome
        Minsk|Europe/Minsk
        Montreal|America/Toronto
        Moscow|Europe/Moscow
        Mumbai|Asia/Kolkata
        Munich|Europe/Berlin
        Nairobi|Africa/Nairobi
        New York|America/New_York
        Osaka|Asia/Tokyo
        Oslo|Europe/Oslo
        Ottawa|America/Toronto
        Paris|Europe/Paris
        Perth|Australia/Perth
        Phoenix|America/Phoenix
        Prague|Europe/Prague
        Reykjavik|Atlantic/Reykjavik
        Riga|Europe/Riga
        Rio de Janeiro|America/Sao_Paulo
        Riyadh|Asia/Riyadh
        Rome|Europe/Rome
        Rotterdam|Europe/Amsterdam
        Saint Petersburg|Europe/Moscow
        San Diego|America/Los_Angeles
        San Francisco|America/Los_Angeles
        Santiago|America/Santiago
        São Paulo|America/Sao_Paulo
        Seattle|America/Los_Angeles
        Seoul|Asia/Seoul
        Shanghai|Asia/Shanghai
        Shenzhen|Asia/Shanghai
        Singapore|Asia/Singapore
        Sofia|Europe/Sofia
        Stockholm|Europe/Stockholm
        Sydney|Australia/Sydney
        Taipei|Asia/Taipei
        Tallinn|Europe/Tallinn
        Tashkent|Asia/Tashkent
        Tbilisi|Asia/Tbilisi
        Tehran|Asia/Tehran
        Tel Aviv|Asia/Jerusalem
        Tokyo|Asia/Tokyo
        Toronto|America/Toronto
        Ulaanbaatar|Asia/Ulaanbaatar
        Vancouver|America/Vancouver
        Vienna|Europe/Vienna
        Vilnius|Europe/Vilnius
        Vladivostok|Asia/Vladivostok
        Warsaw|Europe/Warsaw
        Washington|America/New_York
        Wellington|Pacific/Auckland
        Yerevan|Asia/Yerevan
        Zurich|Europe/Zurich
        """
}
