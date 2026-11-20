package dev.mushroom.clocks

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class ClockTimeTest {
    private val amsterdam = ZoneId.of("Europe/Amsterdam")
    private val seoul = ZoneId.of("Asia/Seoul")
    private val newYork = ZoneId.of("America/New_York")
    private val kolkata = ZoneId.of("Asia/Kolkata")

    private fun at(text: String) = Instant.parse(text)

    @Test fun offsets() {
        val now = at("2026-11-20T11:41:00Z")
        assertEquals("+8h", ClockTime.offset(seoul, now, amsterdam))
        assertEquals("-6h", ClockTime.offset(newYork, now, amsterdam))
        assertEquals("+0h", ClockTime.offset(amsterdam, now, amsterdam))
        assertEquals("+4:30", ClockTime.offset(kolkata, now, amsterdam))
        assertEquals("-4:30", ClockTime.offset(amsterdam, now, kolkata))
    }

    @Test fun home() {
        val now = at("2026-11-20T11:41:00Z")
        assertTrue(ClockTime.isHome(ZoneId.of("Europe/Paris"), now, amsterdam))
        assertFalse(ClockTime.isHome(seoul, now, amsterdam))
    }

    @Test fun phases() {
        // 12:41 in Amsterdam, 06:41 in New York, 20:41 in Seoul.
        val now = at("2026-11-20T11:41:00Z")
        assertEquals(ClockTime.Phase.DAY, ClockTime.phase(amsterdam, now))
        assertEquals(ClockTime.Phase.SUNRISE, ClockTime.phase(newYork, now))
        assertEquals(ClockTime.Phase.NIGHT, ClockTime.phase(seoul, now))
        assertEquals(ClockTime.Phase.SUNSET, ClockTime.phase(amsterdam, at("2026-11-20T18:00:00Z")))
        assertEquals(ClockTime.Phase.NIGHT, ClockTime.phase(amsterdam, at("2026-11-20T23:30:00Z")))
    }

    @Test fun nextChangeIsTheEarliestBoundaryInAnyZone() {
        val now = at("2026-11-20T11:41:00Z")
        // Amsterdam 12:41 -> 18:00 (17:00Z); New York 06:41 -> 08:00 (13:00Z);
        // Seoul 20:41 -> midnight (15:00Z).
        assertEquals(at("2026-11-20T13:00:00Z"), ClockTime.nextChange(now, listOf(amsterdam, newYork, seoul)))
        assertEquals(at("2026-11-20T15:00:00Z"), ClockTime.nextChange(now, listOf(amsterdam, seoul)))
        assertEquals(at("2026-11-20T17:00:00Z"), ClockTime.nextChange(now, listOf(amsterdam)))
    }

    @Test fun nextChangeIsStrictlyAfterNow() {
        val boundary = at("2026-11-20T17:00:00Z") // 18:00 in Amsterdam
        assertEquals(at("2026-11-20T19:00:00Z"), ClockTime.nextChange(boundary, listOf(amsterdam)))
    }

    @Test fun nextChangeRollsOverToTomorrow() {
        // 22:00 in Amsterdam: next is midnight.
        assertEquals(at("2026-11-20T23:00:00Z"), ClockTime.nextChange(at("2026-11-20T21:00:00Z"), listOf(amsterdam)))
    }

    @Test fun nextChangeIncludesDaylightSavingShifts() {
        // Amsterdam springs forward at 01:00Z on 2027-03-28, between midnight
        // (23:00Z the day before) and 05:00 local (03:00Z).
        assertEquals(at("2027-03-28T01:00:00Z"), ClockTime.nextChange(at("2027-03-27T23:30:00Z"), listOf(amsterdam)))
    }
}
