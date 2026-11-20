package dev.mushroom.clocks

import java.time.Instant
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import kotlin.math.abs

/** Time arithmetic for the widget, free of Android so it can be unit tested. */
object ClockTime {
    /**
     * Local hours at which the time-of-day icon changes: sunrise, day, sunset,
     * night. Fixed hours, since a time zone has no single real sunrise.
     */
    val phaseHours = listOf(5, 8, 18, 20)

    enum class Phase { SUNRISE, DAY, SUNSET, NIGHT }

    fun phase(zone: ZoneId, at: Instant): Phase {
        val hour = at.atZone(zone).hour
        return when {
            hour < phaseHours[0] -> Phase.NIGHT
            hour < phaseHours[1] -> Phase.SUNRISE
            hour < phaseHours[2] -> Phase.DAY
            hour < phaseHours[3] -> Phase.SUNSET
            else -> Phase.NIGHT
        }
    }

    private fun offsetSeconds(zone: ZoneId, at: Instant) = zone.rules.getOffset(at).totalSeconds

    /** Difference from this phone's time: "+8h", "-5h", "+5:30", "+0h". */
    fun offset(zone: ZoneId, at: Instant, local: ZoneId = ZoneId.systemDefault()): String {
        val seconds = offsetSeconds(zone, at) - offsetSeconds(local, at)
        val minutes = abs(seconds) / 60
        val sign = if (seconds < 0) "-" else "+"
        return if (minutes % 60 == 0) "$sign${minutes / 60}h"
        else "$sign${minutes / 60}:" + "%02d".format(minutes % 60)
    }

    /** True when the city's clock reads the same as this phone's. */
    fun isHome(zone: ZoneId, at: Instant, local: ZoneId = ZoneId.systemDefault()) =
        offsetSeconds(zone, at) == offsetSeconds(local, at)

    /**
     * The next moment after [now] at which anything on the widget other than
     * the ticking time changes in one of [zones]: midnight (the date), an icon
     * change, or a daylight saving shift (the offsets). The widget wakes for
     * nothing else. Include this phone's own zone, since offsets and the home
     * marker are relative to it.
     */
    fun nextChange(now: Instant, zones: Collection<ZoneId>): Instant {
        val hours = listOf(0) + phaseHours
        return zones.flatMap { zone ->
            val today = now.atZone(zone).toLocalDate()
            val boundaries = (0L..1L).flatMap { day ->
                hours.map { hour ->
                    // atZone moves a time that a daylight saving gap skips to
                    // just after the gap.
                    LocalDateTime.of(today.plusDays(day), LocalTime.of(hour, 0)).atZone(zone).toInstant()
                }
            }
            boundaries + listOfNotNull(zone.rules.nextTransition(now)?.instant)
        }.filter { it > now }.min()
    }
}
