import SwiftUI
import WidgetKit

/// Colours: charcoal grey gradient background, white names, grey dates,
/// orange accent.
enum ClockPalette {
    static let background = LinearGradient(
        colors: [Color(white: 0.17), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
    /// The same gradient as a picture, for the faded look of a desktop widget
    /// that is not in focus. There macOS strips the widget's background and
    /// repaints every shape and text in one pale tint, so a grey fill would
    /// turn into a pale slab that hides the text. Only a picture marked
    /// full-colour is left as it is (see Image.fullColorWhenFaded).
    static let backgroundImage: CGImage? = {
        let height = 64
        guard let context = CGContext(data: nil, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                        colors: [CGColor(gray: 0.17, alpha: 1), CGColor(gray: 0.10, alpha: 1)] as CFArray,
                                        locations: [0, 1])
        else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        return context.makeImage()
    }()
    static let digits = Color.white
    static let colon = Color(white: 0x55 / 255.0) // #555555, faint on the dark background
    /// The date of a city on this Mac's time, brighter than the other dates.
    static let homeDate = Color(white: 0.78)
    static let sun = Color(red: 1.0, green: 0.84, blue: 0.20)
    static let moon = Color(red: 0.64, green: 0.62, blue: 1.0)
    static let label = Color(white: 0.60)
    static let accent = Color(red: 1.0, green: 0.62, blue: 0.04)
    static let home = Color(red: 0.19, green: 0.82, blue: 0.35)
}

extension Image {
    /// Keeps the image's own colours in the faded look of an unfocused desktop
    /// widget, where everything else is repainted in one tint.
    @ViewBuilder func fullColorWhenFaded() -> some View {
        if #available(macOS 15.0, *) { widgetAccentedRenderingMode(.fullColor) } else { self }
    }
}

enum ClockText {
    /// Difference from this Mac's time: "+8h", "-5h", "+5:30", "+0h".
    static func offset(of zone: TimeZone, at date: Date, relativeTo local: TimeZone = .current) -> String {
        let seconds = zone.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        let minutes = abs(seconds) / 60
        let sign = seconds < 0 ? "-" : "+"
        return minutes % 60 == 0
            ? "\(sign)\(minutes / 60)h"
            : "\(sign)\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    /// True when the city's clock reads the same as this Mac's.
    static func isHome(_ zone: TimeZone, at date: Date, relativeTo local: TimeZone = .current) -> Bool {
        zone.secondsFromGMT(for: date) == local.secondsFromGMT(for: date)
    }

    /// Local hours at which the time-of-day icon changes: sunrise, day,
    /// sunset, night. Fixed hours, since a time zone has no single real sunrise.
    static let phaseHours = [5, 8, 18, 20]

    /// For how long from now the widget is planned in full. See timelineDates.
    static let detailedSpan: TimeInterval = 24 * 3600

    /// The moments, from `now` to `days` ahead, at which the widget must be
    /// redrawn because something other than the ticking digits changes in
    /// one of the zones: midnight (the date, and the clock starts over, see
    /// ClocksView.timerText), a time-of-day icon change, or a daylight
    /// saving shift.
    ///
    /// Past `detailedSpan` only what keeps the date and time right is kept:
    /// midnight, 8:00 (the clock drawn at midnight is good until 10:00) and
    /// daylight saving. That part is a reserve for when the system does not
    /// rebuild the timeline on time, and has to be cheap; the icon may then
    /// be out of date.
    static func timelineDates(from now: Date, zones: Set<TimeZone>, days: Int) -> [Date] {
        let horizon = now.addingTimeInterval(Double(days) * 24 * 3600)
        let detailedEnd = now.addingTimeInterval(detailedSpan)
        var dates: Set<Date> = [now]
        for zone in zones {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let today = calendar.startOfDay(for: now)
            var candidates: [Date] = []
            var shift = zone.nextDaylightSavingTimeTransition(after: now)
            while let date = shift, date <= horizon {
                candidates.append(date)
                shift = zone.nextDaylightSavingTimeTransition(after: date)
            }
            for day in 0...days {
                guard let noon = calendar.date(byAdding: .hour, value: 24 * day + 12, to: today) else { continue }
                let start = calendar.startOfDay(for: noon)
                candidates.append(start)
                for hour in phaseHours {
                    guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) else { continue }
                    if date <= detailedEnd || hour == 8 { candidates.append(date) }
                }
            }
            dates.formUnion(candidates.filter { $0 > now && $0 <= horizon })
        }
        return dates.sorted()
    }

    /// SF Symbol and colour for the city's time of day.
    static func dayPhase(in zone: TimeZone, at date: Date) -> (symbol: String, color: Color) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        switch calendar.component(.hour, from: date) {
        case phaseHours[0]..<phaseHours[1]: return ("sunrise.fill", ClockPalette.accent)
        case phaseHours[1]..<phaseHours[2]: return ("sun.max.fill", ClockPalette.sun)
        case phaseHours[2]..<phaseHours[3]: return ("sunset.fill", ClockPalette.accent)
        default: return ("moon.fill", ClockPalette.moon)
        }
    }

    /// The city's date in its country's language and format: "Thursday,
    /// November 12, 2026", "2026년 11월 12일 목요일". `full: false` gives the short
    /// form for narrow columns: "Thu, Nov 12".
    static func date(in city: ClockCity, at date: Date, full: Bool) -> String {
        let locale = city.locale
        var calendar = locale.calendar
        calendar.timeZone = city.timeZone
        let base = Date.FormatStyle(date: full ? .complete : nil, time: nil, locale: locale,
                                    calendar: calendar, timeZone: city.timeZone,
                                    // Each language's own rule for a date shown on its own:
                                    // Dutch capitalises the first word, Swedish does not.
                                    capitalizationContext: .standalone)
        let style = full ? base : base.weekday(.abbreviated).month(.abbreviated).day()
        return date.formatted(style)
    }
}

/// A grid of digital clocks, one row per city, drawn straight on the widget
/// background. Rows have no fill of their own: when the desktop widget is not
/// focused macOS redraws it in a washed-out vibrant style, where a filled panel
/// turns into a bright slab that hides the text on top of it.
struct ClocksView: View {
    /// compact: narrow columns. wide: one full-width column in a short widget,
    /// offsets in a column of their own. roomy: one column with room to stack them.
    enum Size { case compact, wide, roomy }

    var date: Date
    var cities: [ClockCity]
    var columns = 1
    var size: Size = .compact
    var showIcons = true
    /// Ticking seconds after each time, and no blinking colon.
    var showSeconds = false
    /// False draws a steady colon for this Mac's city too (see
    /// ClockText.timelineDates for when).
    var blinks = true

    private var roomy: Bool { size == .roomy }

    /// When a desktop widget is not in focus, macOS redraws it faded (the
    /// vibrant or accented rendering mode), and fixed colours can vanish there.
    /// In those modes every colour gives way to a system style that adapts.
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var fullColor: Bool { renderingMode == .fullColor }

    private func tone(_ color: Color, faded: HierarchicalShapeStyle = .primary) -> AnyShapeStyle {
        fullColor ? AnyShapeStyle(color) : AnyShapeStyle(faded)
    }

    private var rows: [[ClockCity]] {
        stride(from: 0, to: cities.count, by: columns).map {
            Array(cities[$0..<min($0 + columns, cities.count)])
        }
    }

    private var nameSize: CGFloat { [.compact: 13.5, .wide: 17, .roomy: 20][size]! }
    private var offsetSize: CGFloat { [.compact: 9.5, .wide: 12.5, .roomy: 13][size]! }
    /// With seconds the time is set a little smaller, to leave the names room.
    private var timeScale: CGFloat { showSeconds ? 0.88 : 1 }
    private var timeSize: CGFloat { [.compact: 17, .wide: 27, .roomy: 34][size]! * timeScale }
    private var dateSize: CGFloat { [.compact: 9, .wide: 10, .roomy: 12][size]! }
    private var pictureSize: CGFloat { [.compact: 14, .wide: 20, .roomy: 28][size]! }
    private var secondsSize: CGFloat { timeSize * 0.5 }
    /// Two digits and the gap before them.
    private var secondsWidth: CGFloat { secondsSize * 1.4 }
    private var timeWidth: CGFloat { [.compact: 52, .wide: 80, .roomy: 100][size]! * timeScale }
    private var rowHeight: CGFloat { [.compact: 46, .wide: 48, .roomy: 66][size]! }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(tone(Color.white.opacity(0.10), faded: .quaternary)).frame(height: 1)
                }
                HStack(spacing: 18) {
                    ForEach(row) { panel(for: $0) }
                    // Keep a short last row aligned with the columns above it.
                    ForEach(0..<(columns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func panel(for city: ClockCity) -> some View {
        let home = ClockText.isHome(city.timeZone, at: date)
        let phase = ClockText.dayPhase(in: city.timeZone, at: date)

        // City name, with a green location arrow on the cities sharing this
        // Mac's time. An invisible arrow in the text keeps room for it, so a
        // long name and its arrow shrink together; the green one is laid over
        // that, as an image of its own so it keeps its colour when the widget
        // is faded.
        let arrowFont = Font.system(size: nameSize * 0.55, weight: .bold)
        let room = Text(" ") + Text(Image(systemName: "location.fill"))
            .font(arrowFont)
            .foregroundColor(.clear)
        let name = (home ? Text(city.name) + room : Text(city.name))
            .font(.system(size: nameSize, weight: .bold))
            .foregroundStyle(tone(ClockPalette.digits))
            .minimumScaleFactor(0.45)
            .overlay(alignment: Alignment(horizontal: .trailing, vertical: .firstTextBaseline)) {
                if home {
                    Image(systemName: "location.fill")
                        .fullColorWhenFaded()
                        .font(arrowFont)
                        .foregroundStyle(ClockPalette.home)
                        .fixedSize()
                        .offset(y: -nameSize * 0.12)
                }
            }
        let day = Text(ClockText.date(in: city, at: date, full: size != .compact))
            .font(.system(size: dateSize, weight: .semibold))
            .foregroundStyle(tone(home ? ClockPalette.homeDate : ClockPalette.label, faded: .secondary))
            .minimumScaleFactor(0.5) // long dates shrink to fit
        let offset = Text(ClockText.offset(of: city.timeZone, at: date))
            .font(.system(size: offsetSize, weight: .semibold))
            .foregroundStyle(tone(ClockPalette.accent))
            .fixedSize()
        let icon = Image(systemName: phase.symbol)
            .fullColorWhenFaded()
            .font(.system(size: offsetSize + (size == .compact ? 0 : 2), weight: .semibold))
            .foregroundStyle(phase.color)
        let time = liveTime(in: city.timeZone, blinking: home && !showSeconds && blinks)
            .frame(width: timeWidth + (showSeconds ? secondsWidth : 0), alignment: .trailing)
        // A fixed-width column at the far right, so the pictures line up.
        let picture = CountryIcons.image(for: city, points: pictureSize * 1.25)
            .padding(.leading, pictureSize * 0.1)

        // Left: city over its date. Right: the time, with offset and icon in
        // columns of their own when wide, else in a line under the time.
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: roomy ? 1 : -1) { name; day }
                .lineLimit(1)

            Spacer(minLength: 0)

            if size == .wide {
                // Fixed columns, so offsets and icons line up down the widget.
                // No offset for this Mac's own time, but its column stays.
                offset.opacity(home ? 0 : 1).frame(width: 36, alignment: .leading)
                icon.frame(width: 22)
                time
                if showIcons { picture }
            } else {
                VStack(alignment: .trailing, spacing: roomy ? 0 : -2) {
                    time
                    HStack(spacing: 4) { icon; if !home { offset } }
                }
                if showIcons { picture }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: rowHeight)
    }

    /// H:MM, plus small seconds if showSeconds, with a colon that blinks every second for the cities on this Mac's
    /// time and stays lit for the others. A widget cannot redraw
    /// itself, so everything here is a system-driven timer text (see timerText)
    /// seen through a window: one copy shows the hours and minutes with its
    /// colon masked out, another the seconds, and a blinking colon is
    /// two blinkDots, the lower a second behind the upper.
    private func liveTime(in zone: TimeZone, blinking: Bool) -> some View {
        // On the desktop a timer text is laid out as wide as it could ever
        // get, with the digits at its leading edge unless told otherwise. So
        // it is right-aligned in a frame of known width, or the digits would
        // miss the windows below.
        let timer = timerText(in: zone).multilineTextAlignment(.trailing)
            .frame(width: timeSize * 5, alignment: .trailing) // room for all of H:MM:SS
            .fixedSize()
        let width = Self.glyphWidths(size: timeSize)
        let (digit, gap) = (width.digit, width.colon)
        // Dots where San Francisco puts them: centred 0.175 and 0.53 em above the baseline.
        let dot = timeSize * 0.136
        let colon = VStack(spacing: timeSize * 0.355 - dot) {
            // Over four seconds: the upper dot goes for a second, both are
            // lit for a second, the lower goes for a second, both are lit.
            colonDot(in: zone, behind: 0, diameter: dot, blinking: blinking)
            colonDot(in: zone, behind: 2, diameter: dot, blinking: blinking)
        }
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + timeSize * 0.175 - dot / 2 }
            .alignmentGuide(.leading) { $0[HorizontalAlignment.center] - 2 * digit - gap / 2 }
        // HH:MM of the timer: shifted left by the width of its seconds, cut
        // to five characters, and masked to hide its own colon and, from
        // midnight, the 1 of the 10:MM:SS it then reads (see timerText).
        // Widths are measured, and hours and minutes share one timer, because
        // every text in a widget, and a ticking one above all, costs space
        // in the archive the system keeps of it, which has a limit.
        let clock = timer
            .alignmentGuide(.trailing) { $0[.trailing] - 2 * digit - gap }
            .frame(width: 4 * digit + gap, alignment: .trailing)
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    Rectangle().padding(.leading, startsAtMidnight(in: zone) ? digit : 0).frame(width: 2 * digit)
                    Color.clear.frame(width: gap)
                    Rectangle().frame(width: 2 * digit)
                }
            }
            .overlay(alignment: Alignment(horizontal: .leading, vertical: .firstTextBaseline)) { colon }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            clock
            if showSeconds {
                timer
                    .frame(width: 2 * Self.glyphWidths(size: secondsSize).digit, alignment: .trailing)
                    .clipped()
                    .font(.system(size: secondsSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tone(ClockPalette.label, faded: .secondary))
                    .padding(.leading, secondsSize * 0.15)
            }
        }
        .font(.system(size: timeSize, weight: .semibold).monospacedDigit())
        .foregroundStyle(tone(ClockPalette.digits))
        .lineLimit(1)
    }

    @ViewBuilder
    private func colonDot(in zone: TimeZone, behind: TimeInterval, diameter: CGFloat, blinking: Bool) -> some View {
        if blinking {
            blinkDot(in: zone, behind: behind, diameter: diameter)
        } else {
            Circle().fill(tone(ClockPalette.colon, faded: .tertiary)).frame(width: diameter, height: diameter)
        }
    }

    /// A small spot inside a Menlo Bold digit that some digits cover with ink
    /// and the rest leave empty. Found by comparing the digit shapes pixel by
    /// pixel. Sizes are in ems: the side of the square spot, and its centre,
    /// measured left from the digit's right edge and up from the baseline.
    private struct InkSpot {
        let side: CGFloat, left: CGFloat, up: CGFloat
        /// Inked in 0, 2, 4, 6, 8 and empty in 1, 3, 5, 7, 9.
        static let even = InkSpot(side: 0.0547, left: 0.4385, up: 0.1865)
        /// Inked in 0, 5, 6, 8, 9 and empty in every other digit.
        static let upperLeft = InkSpot(side: 0.0742, left: 0.4736, up: 0.5264)
        /// Inked in 0, 3, 4, 5, 6, 8, 9 and empty in every other digit.
        static let lowerRight = InkSpot(side: 0.1035, left: 0.1406, up: 0.2305)
        /// The width of a Menlo digit, to reach the tens of seconds.
        static let digitWidth: CGFloat = 0.602
    }

    /// A dot that is dark for one second in every four (when the seconds
    /// divide by four) and lit for the other three. `behind` delays it by
    /// that many seconds.
    ///
    /// It is made of peepholes onto the seconds of the system timer, set very
    /// large in Menlo Bold so that an InkSpot fills the dot. A peephole is
    /// simply lit while the digit under it has ink at that spot:
    ///   - `odd` is lit on odd seconds: the even spot on a timer a second late;
    ///   - `tensEven` is lit while the tens of seconds are even, `tensOdd`
    ///     (the same on a timer ten seconds late) while they are odd;
    ///   - `units(spot, late)` is lit while the last digit is one of the
    ///     spot's digits plus `late`: the spot on a timer that many seconds late.
    /// The even seconds that do not divide by four end in 2 or 6 when the
    /// tens are even and in 0, 4 or 8 when they are odd. So `tensEven` is
    /// masked by a peephole lit for 2, 3, 5, 6, 7 and `tensOdd` by one lit
    /// for 0, 1, 3, 4, 5, 8, 9 (the odd ones are lit anyway).
    ///
    /// Menlo because macOS fails to draw a widget at all if it uses a font
    /// that does not ship with the system, which rules out a purpose-made
    /// blinking font.
    private func blinkDot(in zone: TimeZone, behind: TimeInterval, diameter: CGFloat) -> some View {
        func units(_ spot: InkSpot, late: Double) -> some View {
            peephole(timerText(in: zone, behind: behind + late), spot: spot, diameter: diameter)
        }
        let odd = units(.even, late: 1)
        let tensEven = peephole(timerText(in: zone, behind: behind), spot: .even, digit: 1, diameter: diameter)
        let tensOdd = peephole(timerText(in: zone, behind: behind + 10), spot: .even, digit: 1, diameter: diameter)
        return ZStack {
            odd
            tensEven.mask { units(.upperLeft, late: 7) }
            tensOdd.mask { units(.lowerRight, late: 5) }
        }
        .clipShape(Circle())
    }

    /// A square window onto one InkSpot of a digit of the timer: the last
    /// digit, or with `digit: 1` the one before it. The font size makes the
    /// spot 1.6 times the window, so that the window stays inside it even if
    /// the system places the text slightly differently.
    private func peephole(_ timer: Text, spot: InkSpot, digit: Int = 0, diameter: CGFloat) -> some View {
        let fontSize = diameter * 1.6 / spot.side
        let left = spot.left + CGFloat(digit) * InkSpot.digitWidth
        let centre = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
        return Color.clear.frame(width: diameter, height: diameter)
            .alignmentGuide(.trailing) { $0.width / 2 }
            .alignmentGuide(.firstTextBaseline) { $0.height / 2 }
            .overlay(alignment: centre) {
                timer.multilineTextAlignment(.trailing)
                    .font(.custom("Menlo-Bold", fixedSize: fontSize))
                    // Swap digits at once: the system's default is to melt one
                    // into the next, which shows as a dot shrinking or growing.
                    .contentTransition(.identity)
                    .foregroundStyle(tone(ClockPalette.colon, faded: .tertiary))
                    .frame(width: fontSize * 6, alignment: .trailing) // room for all of H:MM:SS
                    .fixedSize()
                    .alignmentGuide(.trailing) { $0[.trailing] - fontSize * left }
                    .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] - fontSize * spot.up }
            }
            .clipped()
    }

    /// Width of a digit and of a colon in the font of the time.
    private static func glyphWidths(size: CGFloat) -> (digit: CGFloat, colon: CGFloat) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        func width(_ text: String) -> CGFloat { NSAttributedString(string: text, attributes: [.font: font]).size().width }
        return (width("00") / 2, width("0:0") - width("00"))
    }

    /// True for the view drawn at a city's midnight, which is the one that
    /// shows the hours before 10 through a one-digit window (see timerText).
    private func startsAtMidnight(in zone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.component(.hour, from: date) == 0
    }

    /// 24-hour H:MM:SS as a system-driven timer counting up from the city's
    /// midnight, and stopping at 23:59:59: the system is meant to replace
    /// this view at midnight, and if it is late the clock must not go on to
    /// 24:01.
    ///
    /// A timer under one hour drops its hours and, under ten minutes, the
    /// leading zero of its minutes, which would throw the windows in
    /// liveTime off. So the view drawn at midnight counts from ten hours
    /// earlier and reads 10:MM:SS, of which liveTime hides the 1. That holds
    /// until 9:59:59 (19:59:59), where it stops; a later view (there is one
    /// at 5:00, see ClockText.timelineDates) counts from midnight as usual.
    private func timerText(in zone: TimeZone, behind: TimeInterval = 0) -> Text {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let elapsed = Double((c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0))
            + Double(c.nanosecond ?? 0) / 1e9
        let lead: TimeInterval = c.hour == 0 ? 10 * 3600 : 0
        let start = date.addingTimeInterval(behind - elapsed - lead)
        let end = start.addingTimeInterval((lead > 0 ? 20 : 24) * 3600 - 1)
        return Text(timerInterval: start...end, countsDown: false)
    }
}
