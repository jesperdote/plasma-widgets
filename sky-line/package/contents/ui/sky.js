.pragma library
// Sun and moon maths. The sunrise/sunset formulas follow Vladimir Agafonkin's
// SunCalc (BSD-2-Clause), which is based on https://aa.quae.nl/en/reken/zonpositie.html

var rad = Math.PI / 180
var dayMs = 86400000
var J1970 = 2440588
var J2000 = 2451545
var J0 = 0.0009
var obliquity = rad * 23.4397

function toDays(date) { return date.valueOf() / dayMs - 0.5 + J1970 - J2000 }
function fromJulian(j) { return new Date((j + 0.5 - J1970) * dayMs) }

function meanAnomaly(d) { return rad * (357.5291 + 0.98560028 * d) }
function eclipticLongitude(M) {
    var C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M))
    return M + C + rad * 102.9372 + Math.PI
}
function declination(l) { return Math.asin(Math.sin(obliquity) * Math.sin(l)) }
function transitJ(ds, M, L) { return J2000 + ds + 0.0053 * Math.sin(M) - 0.0069 * Math.sin(2 * L) }

// Sunrise, solar noon and sunset for the local day that contains `date`.
// Returns null near the poles on days the sun doesn't rise or set.
function sunTimes(date, lat, lon) {
    var noonLocal = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12)
    var lw = rad * -lon
    var phi = rad * lat
    var d = toDays(noonLocal)
    var n = Math.round(d - J0 - lw / (2 * Math.PI))
    var ds = J0 + lw / (2 * Math.PI) + n
    var M = meanAnomaly(ds)
    var L = eclipticLongitude(M)
    var dec = declination(L)
    var jNoon = transitJ(ds, M, L)
    var h0 = rad * -0.833 // sun's upper edge on the horizon, with refraction
    var cosW = (Math.sin(h0) - Math.sin(phi) * Math.sin(dec)) / (Math.cos(phi) * Math.cos(dec))
    if (cosW < -1 || cosW > 1)
        return null
    var w = Math.acos(cosW)
    var jSet = transitJ(J0 + (w + lw) / (2 * Math.PI) + n, M, L)
    var jRise = jNoon - (jSet - jNoon)
    return { rise: fromJulian(jRise), noon: fromJulian(jNoon), set: fromJulian(jSet) }
}

// Moon phase from the mean synodic month, counted from the new moon of 2000-01-06 18:14 UTC.
var synodic = 29.530588853
var newMoonRef = Date.UTC(2000, 0, 6, 18, 14)
var phaseNames = ["New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
                  "Full moon", "Waning gibbous", "Last quarter", "Waning crescent"]
var phaseEmoji = ["🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘"]

function moon(date) {
    var age = ((date.valueOf() - newMoonRef) / dayMs) % synodic
    if (age < 0)
        age += synodic
    var idx = Math.floor((age / synodic) * 8 + 0.5) % 8
    var lit = (1 - Math.cos(2 * Math.PI * age / synodic)) / 2
    return { name: phaseNames[idx], emoji: phaseEmoji[idx], illumination: lit, age: age }
}

function hours(date) { return date.getHours() + date.getMinutes() / 60 + date.getSeconds() / 3600 }

function pad(n) { return (n < 10 ? "0" : "") + n }
function hhmm(date) { return pad(date.getHours()) + ":" + pad(date.getMinutes()) }

// Sky colour stops along the 24 hours, keyed to today's sunrise and sunset.
function skyStops(rise, set) {
    var night = "#6E73A8", pink = "#F5BDE6", peach = "#F5A97F", blue = "#8AADF4", noonBlue = "#91D7E3", lilac = "#C6A0F6"
    var noon = (rise + set) / 2
    var s = [[0, night], [rise - 1, night], [rise - 0.25, pink], [rise + 0.5, peach], [rise + 2, blue],
             [noon, noonBlue], [set - 2, blue], [set - 0.5, peach], [set + 0.25, lilac], [set + 1, night], [24, night]]
    return s.filter(function (p) { return p[0] >= 0 && p[0] <= 24 })
}

// Open-Meteo WMO weather code -> emoji and words. Clear nights show the moon's phase.
function weather(code, isDay, moonEmoji) {
    if (code === 0) return { icon: isDay ? "☀️" : moonEmoji, text: "Clear" }
    if (code === 1) return { icon: isDay ? "🌤️" : moonEmoji, text: "Mostly clear" }
    if (code === 2) return { icon: isDay ? "⛅" : "☁️", text: "Partly cloudy" }
    if (code === 3) return { icon: "☁️", text: "Cloudy" }
    if (code === 45 || code === 48) return { icon: "🌫️", text: "Fog" }
    if (code >= 51 && code <= 57) return { icon: "🌦️", text: "Drizzle" }
    if (code >= 61 && code <= 67) return { icon: "🌧️", text: "Rain" }
    if (code >= 71 && code <= 77) return { icon: "🌨️", text: "Snow" }
    if (code >= 80 && code <= 82) return { icon: isDay ? "🌦️" : "🌧️", text: "Rain showers" }
    if (code === 85 || code === 86) return { icon: "🌨️", text: "Snow showers" }
    if (code >= 95) return { icon: "⛈️", text: "Thunderstorm" }
    return { icon: isDay ? "☀️" : moonEmoji, text: "" }
}
