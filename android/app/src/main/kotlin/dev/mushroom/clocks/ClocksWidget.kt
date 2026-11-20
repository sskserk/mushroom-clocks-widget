package dev.mushroom.clocks

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import java.time.Instant
import java.time.ZoneId

/**
 * The home-screen widget, built for the least work on the phone.
 *
 * Each time is a TextClock with the city's zone: the launcher ticks it along
 * with its own clock, so this app is never woken to move the time. The app runs
 * only when something else on the widget changes, which is a handful of times
 * a day: a city's midnight (its date), an icon change at a fixed local hour, a
 * daylight saving shift (the offsets), or the phone's own zone, clock or
 * language changing. For the first three it sets one non-waking alarm at the
 * next such moment (see scheduleNext); the rest arrive as system broadcasts.
 * There is no periodic update (updatePeriodMillis is 0).
 */
class ClocksWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val now = Instant.now()
        ids.forEach { update(context, manager, it, now) }
        scheduleNext(context, now)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id, Instant.now())
    }

    override fun onDisabled(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(refreshIntent(context))
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_LOCALE_CHANGED,
            Intent.ACTION_BOOT_COMPLETED, // alarms do not survive a restart
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> refreshAll(context)
            else -> super.onReceive(context, intent)
        }
    }

    companion object {
        private const val ACTION_REFRESH = "dev.mushroom.clocks.REFRESH"

        /**
         * How late the alarm may come. Android 12 and later stretch any shorter
         * window of an inexact alarm to ten minutes, and an exact alarm needs
         * a permission meant for alarm-clock apps. So a date or icon can turn
         * up to ten minutes late; the time itself is always right.
         */
        private const val WINDOW_MS = 10 * 60 * 1000L

        /** Redraws every placed widget, as after the app changed the cities. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, ClocksWidget::class.java))
            val now = Instant.now()
            ids.forEach { update(context, manager, it, now) }
            if (ids.isNotEmpty()) scheduleNext(context, now)
        }

        private fun update(context: Context, manager: AppWidgetManager, id: Int, now: Instant) {
            manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id), now))
        }

        /**
         * One non-waking alarm (RTC, not RTC_WAKEUP) at the next change. While
         * the screen is off it waits, and fires when the phone next wakes,
         * which is when the widget can next be seen anyway.
         */
        private fun scheduleNext(context: Context, now: Instant) {
            val zones = CityStore.load(context).map { it.zoneId }.toSet() + ZoneId.systemDefault()
            val next = ClockTime.nextChange(now, zones)
            context.getSystemService(AlarmManager::class.java)
                .setWindow(AlarmManager.RTC, next.toEpochMilli(), WINDOW_MS, refreshIntent(context))
        }

        private fun refreshIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, ClocksWidget::class.java).setAction(ACTION_REFRESH),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        /**
         * A layout for each size the launcher may show the widget at (portrait
         * and landscape differ); the launcher picks among them itself, without
         * calling back.
         */
        private fun views(context: Context, options: Bundle, now: Instant): RemoteViews {
            @Suppress("DEPRECATION")
            val reported = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
            val sizes = reported?.takeIf { it.isNotEmpty() }?.distinct() ?: run {
                val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
                val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
                if (minWidth == 0 || maxHeight == 0) listOf(SizeF(180f, 180f))
                else listOf(SizeF(minWidth.toFloat(), maxHeight.toFloat()))
            }
            val cities = CityStore.load(context)
            val settings = CityStore.loadSettings(context)
            val local = ZoneId.systemDefault()
            if (sizes.size == 1) return layout(context, sizes[0], cities, settings, local, now)
            return RemoteViews(sizes.associateWith { layout(context, it, cities, settings, local, now) })
        }

        /** Below this width (dp) the rows are compact: short dates, offsets under the time. */
        private const val WIDE_FROM = 250f

        private fun layout(
            context: Context, size: SizeF, cities: List<ClockCity>, settings: ClockSettings,
            local: ZoneId, now: Instant,
        ): RemoteViews {
            val wide = size.width >= WIDE_FROM
            val rowHeight = if (wide) 46f else 40f
            val count = ((size.height - 12f) / rowHeight).toInt().coerceIn(1, cities.size.coerceAtLeast(1))
            val root = RemoteViews(context.packageName, R.layout.widget)
            root.removeAllViews(R.id.rows)
            cities.take(count).forEachIndexed { index, city ->
                if (index > 0) root.addView(R.id.rows, RemoteViews(context.packageName, R.layout.divider))
                root.addView(R.id.rows, row(context, city, wide, settings, local, now))
            }
            root.setOnClickPendingIntent(
                R.id.root,
                PendingIntent.getActivity(
                    context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            return root
        }

        private fun row(
            context: Context, city: ClockCity, wide: Boolean, settings: ClockSettings, local: ZoneId, now: Instant,
        ): RemoteViews {
            val zone = city.zoneId
            val home = ClockTime.isHome(zone, now, local)
            val views = RemoteViews(context.packageName, if (wide) R.layout.row_wide else R.layout.row_compact)
            views.setTextViewText(R.id.name, city.name)
            // A green arrow after the names of the cities on this phone's time.
            if (home) views.setTextViewCompoundDrawablesRelative(R.id.name, 0, 0, R.drawable.ic_home, 0)
            views.setTextViewText(R.id.date, Regions.date(city, now, full = wide))
            views.setTextColor(R.id.date, context.getColor(if (home) R.color.home_date else R.color.label))
            views.setString(R.id.time, "setTimeZone", zone.id)
            if (settings.showSeconds) {
                views.setString(R.id.seconds, "setTimeZone", zone.id)
                views.setViewVisibility(R.id.seconds, View.VISIBLE)
            }
            views.setImageViewResource(
                R.id.phase,
                when (ClockTime.phase(zone, now)) {
                    ClockTime.Phase.SUNRISE -> R.drawable.ic_sunrise
                    ClockTime.Phase.DAY -> R.drawable.ic_sun
                    ClockTime.Phase.SUNSET -> R.drawable.ic_sunset
                    ClockTime.Phase.NIGHT -> R.drawable.ic_moon
                },
            )
            views.setTextViewText(R.id.offset, ClockTime.offset(zone, now, local))
            return views
        }
    }
}
