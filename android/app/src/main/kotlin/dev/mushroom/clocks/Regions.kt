package dev.mushroom.clocks

import android.icu.text.DateFormat
import android.icu.text.DisplayContext
import android.icu.util.TimeZone
import android.icu.util.ULocale
import java.time.Instant
import java.util.Date

/**
 * Which country a time zone lies in, and from that the language its dates are
 * written in. Android's ICU knows both, so unlike the Mac app no table of
 * zones is needed.
 */
object Regions {
    /** Countries where ICU's "most likely language" guess is not the national language. */
    private val languageOverrides = mapOf("KZ" to "kk-KZ", "BY" to "be-BY")

    private val cache = HashMap<String, ULocale>()

    /** The main language of the zone's country, e.g. Korean for Asia/Seoul. */
    fun locale(zone: String): ULocale = cache.getOrPut(zone) {
        // "001" (the world) for zones without a country, such as UTC.
        val region = runCatching { TimeZone.getRegion(zone) }.getOrNull()
        when {
            region == null || region == "001" -> ULocale.getDefault()
            region in languageOverrides -> ULocale.forLanguageTag(languageOverrides[region])
            else -> ULocale.addLikelySubtags(ULocale("und_$region"))
        }
    }

    /**
     * The city's date in its country's language and format: "Friday, November
     * 20, 2026", "2026년 11월 20일 금요일". `full = false` gives the short form for
     * narrow widgets: "Fri, Nov 20", "11월 20일 (금)".
     */
    fun date(city: ClockCity, at: Instant, full: Boolean): String {
        val locale = locale(city.zone)
        val format = if (full) DateFormat.getDateInstance(DateFormat.FULL, locale)
        else DateFormat.getInstanceForSkeleton("MMMEd", locale)
        format.timeZone = TimeZone.getTimeZone(city.zone)
        // Each language's own rule for a date shown on its own: Dutch
        // capitalises the first word, Swedish does not.
        format.setContext(DisplayContext.CAPITALIZATION_FOR_STANDALONE)
        return format.format(Date.from(at))
    }
}
