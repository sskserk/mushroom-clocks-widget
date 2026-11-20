package dev.mushroom.clocks

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.graphics.Typeface
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.Switch
import android.widget.TextView
import java.time.Instant

/**
 * Chooses the widget's cities and options. Built from platform views only:
 * the app opens rarely, and without AndroidX or Compose it stays small.
 */
class MainActivity : Activity() {
    private lateinit var cities: MutableList<ClockCity>
    private lateinit var chosen: LinearLayout
    private lateinit var results: ArrayAdapter<ClockCity>

    private fun dp(value: Int) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cities = CityStore.load(this).toMutableList()

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(4), dp(20), dp(8))
        }
        header.addView(sectionTitle("Cities on the widget"))
        chosen = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        header.addView(chosen)

        val settings = CityStore.loadSettings(this)
        header.addView(Switch(this).apply {
            text = "Show seconds (uses a little more battery)"
            isChecked = settings.showSeconds
            setPadding(0, dp(16), 0, dp(8))
            setOnCheckedChangeListener { _, checked ->
                CityStore.saveSettings(this@MainActivity, settings.copy(showSeconds = checked))
                ClocksWidget.refreshAll(this@MainActivity)
            }
        })

        val manager = AppWidgetManager.getInstance(this)
        if (manager.isRequestPinAppWidgetSupported) {
            header.addView(Button(this).apply {
                text = "Add widget to home screen"
                setOnClickListener {
                    manager.requestPinAppWidget(ComponentName(this@MainActivity, ClocksWidget::class.java), null, null)
                }
            })
        }

        header.addView(sectionTitle("Add a city"))
        val search = EditText(this).apply {
            hint = "Search cities"
            isSingleLine = true
        }
        header.addView(search)

        results = object : ArrayAdapter<ClockCity>(
            this, android.R.layout.simple_list_item_2, android.R.id.text1, CityCatalog.all.toMutableList(),
        ) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val view = super.getView(position, convertView, parent)
                val city = getItem(position)!!
                view.findViewById<TextView>(android.R.id.text1).text = city.name
                view.findViewById<TextView>(android.R.id.text2).text =
                    "${city.zone.replace('_', ' ')}   ${ClockTime.offset(city.zoneId, Instant.now())}"
                return view
            }
        }
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                results.clear()
                results.addAll(CityCatalog.search(s.toString()))
            }
        })

        val list = ListView(this).apply {
            addHeaderView(header, null, false)
            adapter = results
            setOnItemClickListener { parent, _, position, _ ->
                val city = parent.getItemAtPosition(position) as ClockCity
                if (city !in cities && cities.size < CityStore.MAX_CITIES) {
                    cities.add(city)
                    save()
                }
            }
        }
        setContentView(list)
        renderChosen()
    }

    private fun sectionTitle(text: String) = TextView(this).apply {
        this.text = text
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(getColor(R.color.accent))
        setPadding(0, dp(20), 0, dp(6))
    }

    /** Saves the list and redraws the widgets. */
    private fun save() {
        CityStore.save(this, cities)
        ClocksWidget.refreshAll(this)
        renderChosen()
    }

    private fun renderChosen() {
        chosen.removeAllViews()
        val now = Instant.now()
        cities.forEachIndexed { index, city ->
            val row = LinearLayout(this).apply { gravity = Gravity.CENTER_VERTICAL }
            row.addView(
                TextView(this).apply {
                    text = "${city.name}   ${ClockTime.offset(city.zoneId, now)}"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
                },
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
            )
            fun action(label: String, description: String, enabled: Boolean, act: () -> Unit) =
                row.addView(Button(this, null, android.R.attr.borderlessButtonStyle).apply {
                    text = label
                    contentDescription = description
                    isEnabled = enabled
                    minWidth = dp(44)
                    minimumWidth = dp(44)
                    setOnClickListener { act(); save() }
                })
            action("↑", "Move ${city.name} up", index > 0) { cities.add(index - 1, cities.removeAt(index)) }
            action("↓", "Move ${city.name} down", index < cities.size - 1) {
                cities.add(index + 1, cities.removeAt(index))
            }
            // The widget always shows at least one city.
            action("✕", "Remove ${city.name}", cities.size > 1) { cities.removeAt(index) }
            chosen.addView(row)
        }
    }
}
