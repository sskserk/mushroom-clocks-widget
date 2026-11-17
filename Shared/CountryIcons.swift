import CoreText
import SwiftUI

/// The flag of each clock's country, as an emoji drawn into a picture.
enum CountryIcons {
    /// The flag of the city's country, or a globe for zones without a country
    /// (like UTC).
    static func icon(for city: ClockCity) -> String {
        guard let region = ZoneRegions.region(forZone: city.zone) else { return "🌍" }
        return flag(of: region)
    }

    /// The icon drawn into a bitmap, `points` wide and high. As text, an emoji
    /// is repainted as a flat silhouette in the faded look of an unfocused
    /// desktop widget; a picture marked full-colour is left alone.
    static func image(for city: ClockCity, points: CGFloat) -> some View {
        Group {
            if let bitmap = bitmap(of: icon(for: city), points: points) {
                Image(decorative: bitmap, scale: bitmapScale).fullColorWhenFaded()
            } else {
                Text(icon(for: city)).font(.system(size: points * 0.8))
            }
        }
        .frame(width: points, height: points)
    }

    private static let bitmapScale: CGFloat = 3
    private static let cache = NSCache<NSString, CGImage>()

    private static func bitmap(of emoji: String, points: CGFloat) -> CGImage? {
        let key = "\(emoji)|\(points)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let side = Int((points * bitmapScale).rounded(.up))
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, CGFloat(side) * 0.8, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: emoji, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Centred in the square.
        context.textPosition = CGPoint(x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - ascent - descent) / 2 + descent)
        CTLineDraw(line, context)
        guard let image = context.makeImage() else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// "NL" -> 🇳🇱: a flag is the two letters written as regional indicators.
    private static func flag(of region: String) -> String {
        String(String.UnicodeScalarView(region.unicodeScalars.compactMap { Unicode.Scalar(0x1F1A5 + $0.value) }))
    }
}
