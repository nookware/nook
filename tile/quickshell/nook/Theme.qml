// Nook · Ramen Sign — every colour, font and size the shell uses (tokens.json of the design system).
pragma Singleton
import Quickshell
import QtQuick

Singleton {
    // neutral ground
    readonly property color bg000: "#060606"
    readonly property color bg100: "#0d0d0d"
    readonly property color bg200: "#141414"
    readonly property color bg300: "#202020"
    readonly property color line:  "#343434"
    readonly property color ink:   "#f2f2f2"
    readonly property color muted: "#a8a8a8"
    readonly property color faint: "#626262"
    readonly property color onAccent: "#0d0d0d"

    // nine neons, one per category
    readonly property color rose:   "#ff7a5c"   // media
    readonly property color red:    "#ff6458"   // THE accent: start button, clock, border, glows; time / transfer
    readonly property color orange: "#ff9a3c"   // security / danger, urgent, errors (swapped with red)
    readonly property color gold:   "#ffc247"   // files / places
    readonly property color aqua:   "#4fd8cf"   // dev / shell, success
    readonly property color cyan:   "#45c8e6"   // FOCUS + comms
    readonly property color blue:   "#62a5ff"   // network / web
    readonly property color amber:  "#ffb14a"   // system
    readonly property color cream:  "#ffd98f"   // session

    // fire → ice, for big ASCII rows
    readonly property var rainbow: [rose, red, orange, gold, aqua, cyan, blue, amber, cream]

    function soft(c) { return Qt.rgba(c.r, c.g, c.b, 0.16) }      // <hue>-soft
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    readonly property string font:  "JetBrains Mono"
    readonly property string pixel: "VT323"

    // type scale
    readonly property int body:  13
    readonly property int small: 11
    readonly property int label: 10

    // shape
    readonly property int bar:      30     // the bar: a strip flush on the bottom edge
    readonly property int pill:     24     // bar module height, inside the strip
    readonly property int gap:      8      // space-2: between bar modules
    readonly property int pad:      12     // space-3: panel padding
    readonly property int edge:     6      // gaps_out: windows to the screen edges and the bar
    readonly property int radius:   4      // radius-md = Hyprland rounding
    readonly property int radiusSm: 2      // key caps, rows, workspace marks
}
