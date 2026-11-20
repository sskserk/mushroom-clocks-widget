package dev.mushroom.clocks

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.time.ZoneId

/** One clock: a display name and its time zone identifier. */
data class ClockCity(val name: String, val zone: String) {
    val zoneId: ZoneId get() = runCatching { ZoneId.of(zone) }.getOrElse { ZoneId.systemDefault() }
}

/** Display options, saved next to the cities. */
data class ClockSettings(
    /**
     * Small ticking seconds after each time. Off by default: the launcher then
     * redraws the widget every second instead of every minute.
     */
    val showSeconds: Boolean = false,
)

/** The chosen cities and settings: written by the app, read by the widget. */
object CityStore {
    const val MAX_CITIES = 10
    private const val PREFS = "clocks"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun load(context: Context): List<ClockCity> {
        val json = prefs(context).getString("cities", null) ?: return defaults()
        val cities = runCatching {
            val array = JSONArray(json)
            (0 until array.length()).map { array.getJSONObject(it) }
                .map { ClockCity(it.getString("name"), it.getString("zone")) }
        }.getOrDefault(emptyList())
        return cities.ifEmpty { defaults() }.take(MAX_CITIES)
    }

    fun save(context: Context, cities: List<ClockCity>) {
        val array = JSONArray()
        cities.take(MAX_CITIES).forEach { array.put(JSONObject().put("name", it.name).put("zone", it.zone)) }
        prefs(context).edit().putString("cities", array.toString()).apply()
    }

    fun loadSettings(context: Context) =
        ClockSettings(showSeconds = prefs(context).getBoolean("showSeconds", false))

    fun saveSettings(context: Context, settings: ClockSettings) {
        prefs(context).edit().putBoolean("showSeconds", settings.showSeconds).apply()
    }

    /** Used until a list is saved: this phone's zone plus three far-apart cities. */
    fun defaults(): List<ClockCity> {
        val local = ZoneId.systemDefault().id
        val others = listOf("London" to "Europe/London", "New York" to "America/New_York", "Tokyo" to "Asia/Tokyo")
            .filter { it.second != local }
            .map { ClockCity(it.first, it.second) }
        return listOf(ClockCity(CityCatalog.cityName(local), local)) + others
    }
}

/** Every city the app's search offers. */
object CityCatalog {
    fun cityName(zone: String) = zone.substringAfterLast('/').replace('_', ' ')

    /** Zone areas with real cities; leaves out aliases like US/Eastern and Etc/GMT+1. */
    private val areas = setOf(
        "Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic", "Australia", "Europe", "Indian", "Pacific",
    )

    /**
     * Old names the time zone database keeps for compatibility, each a copy of
     * a zone listed under its current name (Australia/ACT is Australia/Sydney).
     * The Mac's list leaves them out; Android's does not.
     */
    private val aliases = setOf(
        "Africa/Asmera", "Africa/Timbuktu", "America/Argentina/ComodRivadavia", "America/Atka",
        "America/Buenos_Aires", "America/Catamarca", "America/Coral_Harbour", "America/Cordoba",
        "America/Ensenada", "America/Fort_Wayne", "America/Indianapolis", "America/Jujuy",
        "America/Knox_IN", "America/Louisville", "America/Mendoza", "America/Porto_Acre",
        "America/Rosario", "America/Virgin", "Asia/Ashkhabad", "Asia/Chungking",
        "Asia/Dacca", "Asia/Istanbul", "Asia/Macao", "Asia/Saigon",
        "Asia/Tel_Aviv", "Asia/Thimbu", "Asia/Ujung_Pandang", "Asia/Ulan_Bator",
        "Atlantic/Faeroe", "Atlantic/Jan_Mayen", "Australia/ACT", "Australia/Canberra",
        "Australia/LHI", "Australia/NSW", "Australia/North", "Australia/Queensland",
        "Australia/South", "Australia/Tasmania", "Australia/Victoria", "Australia/West",
        "Australia/Yancowinna", "Europe/Belfast", "Europe/Nicosia", "Europe/Tiraspol",
        "Pacific/Samoa", "Pacific/Yap",
    )

    /** Curated names plus every city in the time zone database, A to Z. */
    val all: List<ClockCity> by lazy {
        val curated = curatedList.lines().mapNotNull { line ->
            val parts = line.trim().split('|')
            if (parts.size == 2) ClockCity(parts[0], parts[1]) else null
        }
        val seen = curated.map { it.name.lowercase() }.toMutableSet()
        val fromSystem = ZoneId.getAvailableZoneIds()
            .filter { it.substringBefore('/') in areas && '/' in it && it !in aliases }
            .map { ClockCity(cityName(it), it) }
            .filter { seen.add(it.name.lowercase()) }
        (curated + fromSystem).sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    /** Matches whose name starts with the text come first. */
    fun search(text: String): List<ClockCity> {
        val needle = text.trim().lowercase()
        if (needle.isEmpty()) return all
        val (prefix, inside) = all.filter { needle in it.name.lowercase() }
            .partition { it.name.lowercase().startsWith(needle) }
        return prefix + inside
    }

    /** "Name|time zone". Includes well-known cities that share another city's zone. */
    private val curatedList = """
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
