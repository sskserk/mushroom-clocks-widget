package dev.mushroom.clocks

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.res.ColorStateList
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
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
 * Styled like the widget: charcoal cards, white names, orange accents.
 */
class MainActivity : Activity() {
    private lateinit var cities: MutableList<ClockCity>
    private lateinit var chosen: LinearLayout
    private lateinit var results: ArrayAdapter<ClockCity>

    private fun dp(value: Int) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics).toInt()

    private fun rounded(color: Int, radiusDp: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radiusDp).toFloat()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cities = CityStore.load(this).toMutableList()

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(28), dp(20), dp(8))
        }
        header.addView(TextView(this).apply {
            text = "Mushroom Clocks"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(getColor(R.color.digits))
        })
        header.addView(TextView(this).apply {
            text = "Choose the cities on your widget."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(getColor(R.color.label))
            setPadding(0, dp(2), 0, 0)
        })

        header.addView(sectionTitle("Your cities"))
        chosen = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        header.addView(chosen)

        val settings = CityStore.loadSettings(this)
        header.addView(sectionTitle("Options"))
        header.addView(Switch(this).apply {
            text = "Show seconds"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(getColor(R.color.digits))
            isChecked = settings.showSeconds
            background = rounded(getColor(R.color.surface), 14)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            // Accent-coloured when on, grey when off.
            val states = arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf())
            thumbTintList = ColorStateList(states, intArrayOf(getColor(R.color.accent), getColor(R.color.label)))
            trackTintList = ColorStateList(states, intArrayOf(getColor(R.color.accent_soft), 0x33FFFFFF))
            setOnCheckedChangeListener { _, checked ->
                CityStore.saveSettings(this@MainActivity, settings.copy(showSeconds = checked))
                ClocksWidget.refreshAll(this@MainActivity)
            }
        })
        header.addView(TextView(this).apply {
            text = "Ticking seconds use a little more battery."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setTextColor(getColor(R.color.label))
            setPadding(dp(4), dp(6), 0, 0)
        })

        val manager = AppWidgetManager.getInstance(this)
        if (manager.isRequestPinAppWidgetSupported) {
            header.addView(
                Button(this).apply {
                    text = "Add widget to home screen"
                    isAllCaps = false
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(getColor(R.color.on_accent))
                    background = rounded(getColor(R.color.accent), 14)
                    stateListAnimator = null
                    setOnClickListener {
                        manager.requestPinAppWidget(ComponentName(this@MainActivity, ClocksWidget::class.java), null, null)
                    }
                },
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(50)).apply { topMargin = dp(20) },
            )
        }

        header.addView(sectionTitle("Add a city"))
        val search = EditText(this).apply {
            hint = "Search cities"
            isSingleLine = true
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setTextColor(getColor(R.color.digits))
            background = rounded(getColor(R.color.surface), 14)
            setPadding(dp(16), dp(12), dp(16), dp(12))
        }
        header.addView(search)

        results = object : ArrayAdapter<ClockCity>(
            this, android.R.layout.simple_list_item_2, android.R.id.text1, CityCatalog.all.toMutableList(),
        ) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val view = super.getView(position, convertView, parent)
                val city = getItem(position)!!
                view.setPadding(dp(20), dp(8), dp(20), dp(8))
                view.findViewById<TextView>(android.R.id.text1).apply {
                    text = city.name
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
                    setTextColor(getColor(R.color.digits))
                }
                view.findViewById<TextView>(android.R.id.text2).apply {
                    text = "${city.zone.replace('_', ' ')}  ·  ${ClockTime.offset(city.zoneId, Instant.now())}"
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    setTextColor(getColor(R.color.label))
                }
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
            divider = ColorDrawable(getColor(R.color.divider))
            dividerHeight = 1
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
        this.text = text.uppercase()
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        typeface = Typeface.DEFAULT_BOLD
        letterSpacing = 0.1f
        setTextColor(getColor(R.color.accent))
        setPadding(dp(4), dp(24), 0, dp(8))
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
            val row = LinearLayout(this).apply {
                gravity = Gravity.CENTER_VERTICAL
                background = rounded(getColor(R.color.surface), 14)
                setPadding(dp(16), dp(2), dp(6), dp(2))
            }
            row.addView(
                TextView(this).apply {
                    text = city.name
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(getColor(R.color.digits))
                    isSingleLine = true
                },
                LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
            )
            row.addView(TextView(this).apply {
                text = ClockTime.offset(city.zoneId, now)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(getColor(R.color.accent))
                background = rounded(getColor(R.color.accent_soft), 10)
                setPadding(dp(8), dp(2), dp(8), dp(2))
            })
            fun action(label: String, description: String, enabled: Boolean, act: () -> Unit) =
                row.addView(Button(this, null, android.R.attr.borderlessButtonStyle).apply {
                    text = label
                    contentDescription = description
                    isEnabled = enabled
                    alpha = if (enabled) 1f else 0.25f
                    setTextColor(getColor(R.color.label))
                    minWidth = dp(42)
                    minimumWidth = dp(42)
                    setOnClickListener { act(); save() }
                })
            action("↑", "Move ${city.name} up", index > 0) { cities.add(index - 1, cities.removeAt(index)) }
            action("↓", "Move ${city.name} down", index < cities.size - 1) {
                cities.add(index + 1, cities.removeAt(index))
            }
            // The widget always shows at least one city.
            action("✕", "Remove ${city.name}", cities.size > 1) { cities.removeAt(index) }
            chosen.addView(
                row,
                LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
                    .apply { bottomMargin = dp(6) },
            )
        }
    }
}
