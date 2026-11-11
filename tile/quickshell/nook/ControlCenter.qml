// The control center: everything extra, in the launcher's style, above the clock on the bar's right.
//   [ audio ]  output and input device, volume, mute, a mixer per app
//   [ net ]    wired links and their profiles (bin/nook-wired), wifi on/off and networks
//   [ bt ]     bluetooth on/off, scan, devices with connect and battery
//   [ apps ]   background apps (the tray) as a list, and what's playing
//   [ nook ]   what the bar and the desktop show (Settings.qml), homelab hosts, weather place
// Opened from the bar (a click on the clock, right-click λ nook → nook), SUPER A (last tab),
// SUPER N (net), SUPER ⇧ B (bt), or IPC:
//   qs -c nook ipc call control toggle audio|net|bt|apps|nook      … control last
//
// All of it works from the keyboard: ↑↓ (or j k) move the focus, ⏎ / space press, ←→ change a
// level, del forgets / removes, m opens a tray app's menu, tab ⇧tab or 1‥5 switch tabs, esc closes.
// Each focusable part has a navKey; rows are rebuilt whenever their list changes (wifi signal,
// nmcli polls), and a rebuilt row with the focused key takes the focus back.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Bluetooth
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Scope {
    id: root

    readonly property var tabs: [
        { id: "audio", hue: Theme.rose },
        { id: "net",   hue: Theme.blue },
        { id: "bt",    hue: Theme.cyan },
        { id: "apps",  hue: Theme.amber },
        { id: "nook",  hue: Theme.red }
    ]

    IpcHandler {
        target: "control"
        function toggle(tab: string): void { Ui.openControl(tab || Ui.controlTab) }
        function last(): void { Ui.toggleControl() }
        function close(): void { Ui.controlOpen = false }
        function rescan(): void { nm.running = true }
    }

    // ── audio: nodes by media.class ──
    readonly property var nodes: Pipewire.nodes.values
    function cls(n) { return n?.properties?.["media.class"] ?? "" }
    readonly property var sinks:   nodes.filter(n => cls(n) === "Audio/Sink")
    readonly property var sources: nodes.filter(n => cls(n) === "Audio/Source")
    readonly property var streams: nodes.filter(n => cls(n) === "Stream/Output/Audio")
    PwObjectTracker { objects: root.sinks.concat(root.sources, root.streams) }
    function label(n) { return n?.nickname || n?.description || n?.name || "?" }
    function appName(n) {
        const p = n?.properties ?? {};
        return (p["application.name"] || p["node.name"] || n?.name || "app").toLowerCase();
    }

    // ── wired links and profiles: Quickshell's network module only knows wifi, so bin/nook-wired
    //    asks nmcli. A profile bound to a MAC / interface goes to its own adapter, any other one to
    //    wiredTarget (the [on <dev>] button cycles through the adapters with a cable). ──
    readonly property string wiredBin: Quickshell.env("HOME") + "/.local/bin/nook-wired"
    property var wired: []                // {dev, state, profile, mac, cable}
    property var profiles: []             // {uuid, name, active, bound, method, address}
    property string wiredTarget: ""
    property string wiredBusy: ""         // uuid being switched
    readonly property var cabled: root.wired.filter(d => d.cable)
    readonly property string target: root.cabled.some(d => d.dev === root.wiredTarget) ? root.wiredTarget
        : (root.cabled.find(d => d.state === "connected") ?? root.cabled[0])?.dev ?? ""
    function cycleTarget() {
        const i = root.cabled.findIndex(d => d.dev === root.target);
        if (root.cabled.length) root.wiredTarget = root.cabled[(i + 1) % root.cabled.length].dev;
    }
    function profileNote(p) {
        const ip = p.method === "auto" ? "dhcp" : p.method === "manual" ? (p.address || "static") : p.method === "disabled" ? "no ipv4" : p.method;
        if (root.wiredBusy === p.uuid) return "switching…  " + ip;
        if (p.active) return "on " + p.active + "  " + ip;
        if (p.bound === "missing") return "adapter not here  " + ip;
        return (p.bound ? "→ " + p.bound + "  " : "") + ip;
    }
    function wiredProfile(p) {
        root.netError = "";
        root.wiredBusy = p.uuid;
        wiredAct.command = p.active ? [root.wiredBin, "down", p.uuid] : [root.wiredBin, "up", p.uuid].concat(root.target ? [root.target] : []);
        wiredAct.running = true;
    }
    Process {
        id: nm
        command: [root.wiredBin, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(this.text);
                    root.wired = j.devices;
                    root.profiles = j.profiles;
                } catch (e) {}
            }
        }
    }
    Process {
        id: wiredAct
        stderr: StdioCollector { onStreamFinished: if (this.text.trim() !== "") root.netError = this.text.trim().replace(/^nook-wired: /, "") }
        onExited: { root.wiredBusy = ""; nm.running = true }
    }
    Timer { interval: 5000; repeat: true; triggeredOnStart: true; running: Ui.controlOpen && Ui.controlTab === "net"; onTriggered: nm.running = true }

    // tray items that only have a menu (Ayatana ones say so nowhere; nook-tray-menuonly checks D-Bus)
    property var trayMenuOnly: []
    Process {
        id: trayProbe
        command: ["nook-tray-menuonly"]
        stdout: StdioCollector { onStreamFinished: root.trayMenuOnly = this.text.split("\n").filter(l => l !== "") }
    }
    Timer { interval: 10000; repeat: true; triggeredOnStart: true; running: Ui.controlOpen && Ui.controlTab === "apps"; onTriggered: trayProbe.running = true }
    Connections { target: SystemTray.items; ignoreUnknownSignals: true; function onValuesChanged() { trayProbe.running = true } }

    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNets: (wifiDev?.networks?.values ?? []).slice()
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))

    // wifi scans while the net tab is open
    Binding {
        when: root.wifiDev !== null
        target: root.wifiDev
        property: "scannerEnabled"
        value: Ui.controlOpen && Ui.controlTab === "net"
    }
    function nmcli(args) { Quickshell.execDetached(["sh", "-c", "nmcli \"$@\" >/dev/null 2>&1; qs -c nook ipc call control rescan", "nmcli"].concat(args)) }
    // Quickshell 0.3 renamed the network enums and added connectionFailed / connectWithPsk;
    // 0.2 (Fedora's package) has NetworkState, nmReason and no psk call. Both are handled.
    readonly property var netState: typeof ConnectionState !== "undefined" ? ConnectionState : NetworkState
    readonly property var failReason: typeof ConnectionFailReason !== "undefined" ? ConnectionFailReason : NMConnectionStateReason
    function wifiFailed(net, ssid, open, reason) {
        if (reason === undefined || reason === failReason.None || reason === failReason.Unknown || net.connected) return;
        root.netError = ssid + ": " + failReason.toString(reason).toLowerCase();
        if (reason === failReason.NoSecrets && !open) root.pskFor = net.name;
    }
    function joinWithPsk(net, psk) {
        if (typeof net.connectWithPsk === "function") net.connectWithPsk(psk);
        else root.nmcli(["device", "wifi", "connect", net.name, "password", psk]);
    }
    function netSettings() {
        Ui.controlOpen = false;
        Quickshell.execDetached(["sh", "-c", "command -v nm-connection-editor >/dev/null && exec nm-connection-editor || exec kitty -e nmtui"]);
    }

    property string pskFor: ""            // the wifi network asking for its password
    property string pskText: ""
    property bool pskShown: false
    property string netError: ""
    property string pairingWith: ""       // bt address we paired from here: trust + connect when done
    // destructive row actions (forget, remove) need a second click within 3 s
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: root.armed = "" }
    function confirm(id) {
        if (root.armed === id) { root.armed = ""; disarm.stop(); return true; }
        root.armed = id;
        disarm.restart();
        return false;
    }

    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btDevices: (bt?.devices?.values ?? []).slice()
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || (a.name ?? "").localeCompare(b.name ?? ""))

    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    function bars(v, n) { const k = Math.round(Math.max(0, Math.min(1, v)) * n); return "█".repeat(k) + "░".repeat(n - k) }
    function signal(s) { const k = Math.round(s * 4); return "▂▄▆█".slice(0, k).padEnd(4, " ") }

    // ── keyboard focus ──
    property string navKey: ""            // what has the focus, survives a rebuilt row
    function focused(it) {
        root.navKey = it.navKey;
        root.reveal(it);
    }
    function grab(it) {
        if (typeof it.focusIn === "function") it.focusIn();
        else it.forceActiveFocus();
    }
    function restore(it) {
        if (!Ui.controlOpen || it.navKey === "" || it.navKey !== root.navKey) return;
        Qt.callLater(() => { if (it && it.visible) root.grab(it) });
    }
    // the next / previous focusable part of the open tab (the focus chain wraps)
    function nav(forward) {
        const from = root.focusAt(card) ?? card;
        const n = from.nextItemInFocusChain(forward);
        if (n && n !== card) n.forceActiveFocus();
    }
    function focusAt(it) {
        if (it.activeFocus && it.activeFocusOnTab) return it;
        for (const c of it.children) { const f = root.focusAt(c); if (f) return f; }
        return null;
    }
    function focusFirst() {
        root.navKey = "";
        card.forceActiveFocus();
        root.nav(true);
        flick.contentY = 0;
    }
    function reveal(it) {
        const y = it.mapToItem(body, 0, 0).y;
        if (y - 8 < flick.contentY) flick.contentY = Math.max(0, y - 8);
        else if (y + it.height + 8 > flick.contentY + flick.height)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), y + it.height + 8 - flick.height);
    }
    function nextTab(step) {
        const i = root.tabs.findIndex(t => t.id === Ui.controlTab);
        Ui.controlTab = root.tabs[(i + step + root.tabs.length) % root.tabs.length].id;
    }
    Connections {
        target: Ui
        function onControlTabChanged() { if (Ui.controlOpen) Qt.callLater(root.focusFirst) }
    }

    // ── small parts in the design system's look ──
    component Mono: Text {
        color: Theme.ink
        font.family: Theme.font
        font.pixelSize: 12
        elide: Text.ElideRight
    }
    component Label: Mono {
        color: Theme.faint
        font.pixelSize: Theme.label
        font.bold: true
        font.letterSpacing: 1.2
        Layout.topMargin: 6
        Layout.bottomMargin: 2
    }
    // [ text ] button: outlined in its hue, filled when on; ⏎ / space press it
    component Btn: Rectangle {
        id: btn
        property string text
        property color hue: Theme.cyan
        property bool on: false
        property bool nav: true               // false: reached another way (tabs, row actions)
        property string navKey: nav ? "btn:" + text : ""
        signal clicked()
        activeFocusOnTab: nav
        onActiveFocusChanged: if (activeFocus) root.focused(btn)
        Component.onCompleted: root.restore(btn)
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { btn.clicked(); e.accepted = true; }
        }
        implicitWidth: bt_.implicitWidth + 16
        implicitHeight: 22
        radius: Theme.radiusSm
        color: on ? hue : btnArea.containsMouse || activeFocus ? Theme.soft(hue) : "transparent"
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? Theme.cyan : hue
        Mono { id: bt_; anchors.centerIn: parent; text: btn.text; color: btn.on ? Theme.onAccent : btn.hue; font.pixelSize: Theme.small; font.bold: btn.on }
        MouseArea { id: btnArea; anchors.fill: parent; hoverEnabled: true; onClicked: btn.clicked() }
    }
    // a selectable row: [•] name ........ note, cyan ring when it's the current one
    // An optional [action] button at the end (forget, remove …) sits on top of the row's click.
    // Keys: ⏎ / space = click, del = the action.
    component Row: Rectangle {
        id: row
        property string name
        property string note
        property color hue: Theme.ink
        property bool current: false
        property string action: ""
        property color actionHue: Theme.orange
        property string navKey: "row:" + name
        signal clicked()
        signal actionClicked()
        activeFocusOnTab: true
        onActiveFocusChanged: if (activeFocus) root.focused(row)
        Component.onCompleted: root.restore(row)
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { row.clicked(); e.accepted = true; }
            else if ((e.key === Qt.Key_Delete || e.key === Qt.Key_Backspace) && row.action !== "") { row.actionClicked(); e.accepted = true; }
        }
        Layout.fillWidth: true
        implicitHeight: 24
        radius: Theme.radiusSm
        color: current ? Theme.soft(Theme.cyan) : rowArea.containsMouse || activeFocus ? Theme.bg300 : "transparent"
        border.width: activeFocus ? 2 : current || rowArea.containsMouse ? 1 : 0
        border.color: current || activeFocus ? Theme.cyan : Theme.line
        MouseArea { id: rowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: row.clicked() }
        RowLayout {
            anchors { fill: parent; leftMargin: 6; rightMargin: 4 }
            spacing: 8
            Mono { text: row.current ? "[•]" : row.activeFocus ? "[>]" : "[ ]"; color: row.current || row.activeFocus ? Theme.cyan : Theme.faint }
            Mono { text: row.name; color: row.hue; Layout.maximumWidth: 230 }
            Mono { text: ".".repeat(80); color: Theme.faint; Layout.fillWidth: true; clip: true; elide: Text.ElideNone }
            Mono { text: row.note; color: Theme.muted; font.pixelSize: Theme.small }
            Btn {
                visible: row.action !== ""
                text: row.action
                hue: row.actionHue
                nav: false
                implicitHeight: 18
                onClicked: row.actionClicked()
            }
        }
    }
    // [x] name  note: a compact on/off switch for the nook tab
    component Check: Rectangle {
        id: chk
        property string name
        property string note
        property bool on: true
        property color hue: Theme.red
        property string navKey: "chk:" + name
        signal toggled()
        activeFocusOnTab: true
        onActiveFocusChanged: if (activeFocus) root.focused(chk)
        Component.onCompleted: root.restore(chk)
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { chk.toggled(); e.accepted = true; }
        }
        Layout.fillWidth: true
        implicitHeight: 22
        radius: Theme.radiusSm
        color: chkArea.containsMouse || activeFocus ? Theme.bg300 : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.cyan
        RowLayout {
            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
            spacing: 6
            Mono { text: chk.on ? "[x]" : "[ ]"; color: chk.on ? chk.hue : Theme.faint; font.bold: chk.on }
            Mono { text: chk.name; color: chk.on ? Theme.ink : Theme.muted }
            Mono { text: chk.note; color: Theme.faint; font.pixelSize: Theme.label; Layout.fillWidth: true }
        }
        MouseArea { id: chkArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chk.toggled() }
    }
    // a one-line text field; ⏎ accepts, esc cancels (closes when empty), ↑↓ leave it
    component Field: Rectangle {
        id: field
        property alias text: input.text
        property string placeholder
        property bool secret: false
        property color hue: Theme.cyan
        property string navKey: "field:" + placeholder
        signal accepted()
        signal cancelled()
        function focusIn() { input.forceActiveFocus() }
        Component.onCompleted: root.restore(field)
        Layout.fillWidth: true
        implicitHeight: 24
        radius: Theme.radiusSm
        color: Theme.bg200
        border.width: 1
        border.color: input.activeFocus ? field.hue : Theme.line
        MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: input.forceActiveFocus() }
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 7; rightMargin: 7 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.ink
            selectionColor: field.hue
            selectedTextColor: Theme.onAccent
            font.family: Theme.font
            font.pixelSize: 12
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            clip: true
            selectByMouse: true
            activeFocusOnTab: true
            onActiveFocusChanged: if (activeFocus) root.focused(field)
            onAccepted: field.accepted()
            // esc in an empty field falls through and closes the panel; tab switches tabs
            Keys.onEscapePressed: e => { if (text === "") e.accepted = false; else field.cancelled() }
            Keys.onUpPressed: root.nav(false)
            Keys.onDownPressed: root.nav(true)
        }
        Mono {
            anchors { fill: parent; leftMargin: 7 }
            verticalAlignment: Text.AlignVCenter
            visible: input.text === "" && !input.activeFocus
            text: field.placeholder
            color: Theme.faint
        }
    }
    // [██████░░░░] 60%: click or drag to set, scroll for ±5%; keys ←→ ±5% (⇧ ±1%), ⏎ / m mute
    component Level: Rectangle {
        id: lvl
        property real value: 0
        property bool muted: false
        property color hue: Theme.rose
        property string name: "vol"
        property string navKey: "lvl:" + name
        signal picked(real v)
        signal toggleMute()
        activeFocusOnTab: true
        onActiveFocusChanged: if (activeFocus) root.focused(lvl)
        Component.onCompleted: root.restore(lvl)
        Keys.onPressed: e => {
            const step = (e.modifiers & Qt.ShiftModifier) ? 0.01 : 0.05;
            if (e.key === Qt.Key_Left || e.key === Qt.Key_H) lvl.picked(Math.max(0, lvl.value - step));
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_L) lvl.picked(Math.min(1, lvl.value + step));
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || e.key === Qt.Key_M) lvl.toggleMute();
            else return;
            e.accepted = true;
        }
        Layout.fillWidth: true
        implicitHeight: 26
        implicitWidth: lvlRow.implicitWidth + 8
        radius: Theme.radiusSm
        color: activeFocus ? Theme.bg300 : "transparent"
        border.width: activeFocus ? 1 : 0
        border.color: Theme.cyan
      RowLayout {
        id: lvlRow
        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
        spacing: 8
        Mono { text: lvl.name; color: Theme.muted; Layout.preferredWidth: 34 }
        Mono {
            id: barText
            Layout.fillWidth: true
            text: "[" + root.bars(lvl.value, 24) + "]"
            color: lvl.muted ? Theme.faint : lvl.hue
            elide: Text.ElideNone
            MouseArea {
                anchors.fill: parent
                function at(x) { lvl.picked(Math.max(0, Math.min(1, (x - 7) / (barText.contentWidth - 14)))) }
                onPressed: m => at(m.x)
                onPositionChanged: m => { if (pressed) at(m.x) }
                onWheel: w => lvl.picked(Math.max(0, Math.min(1, lvl.value + (w.angleDelta.y > 0 ? 0.05 : -0.05))))
            }
        }
        Mono { text: lvl.muted ? "mute" : Math.round(lvl.value * 100) + "%"; color: lvl.muted ? Theme.faint : Theme.ink; Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight }
        Btn { text: lvl.muted ? "unmute" : "mute"; hue: Theme.orange; on: lvl.muted; nav: false; onClicked: lvl.toggleMute() }
      }
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: Ui.controlOpen && panel.visible
        onCleared: Ui.controlOpen = false
    }

    PanelWindow {
        id: panel
        visible: Ui.controlOpen
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "nook-control"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true; right: true }
        margins { bottom: Theme.pill + 10 + Theme.gap; right: Theme.pad }
        implicitWidth: 580
        implicitHeight: Math.min(card.implicitHeight, (screen?.height ?? 1440) - 120) + 20
        color: "transparent"
        onVisibleChanged: if (visible) focusTimer.restart()
        // the layer surface takes keyboard focus a moment after it maps
        Timer { id: focusTimer; interval: 50; onTriggered: root.focusFirst() }

        RectangularShadow {
            anchors.fill: card
            radius: Theme.radius
            blur: 24
            color: Theme.alpha(Theme.cyan, 0.45)
        }

        Rectangle {
            id: card
            x: 10; y: 10
            width: 560
            height: parent.height - 20
            implicitHeight: body.implicitHeight + 2
            radius: Theme.radius
            color: Theme.bg100
            border.width: 1
            border.color: Theme.cyan
            clip: true
            focus: true
            // whatever the focused part didn't take ends up here
            Keys.onPressed: e => {
                const k = e.key;
                if (k === Qt.Key_Escape) Ui.controlOpen = false;
                else if (k === Qt.Key_Tab) root.nextTab(1);
                else if (k === Qt.Key_Backtab) root.nextTab(-1);
                else if (k === Qt.Key_Down || k === Qt.Key_J) root.nav(true);
                else if (k === Qt.Key_Up || k === Qt.Key_K) root.nav(false);
                else if (k >= Qt.Key_1 && k < Qt.Key_1 + root.tabs.length) Ui.controlTab = root.tabs[k - Qt.Key_1].id;
                else return;
                e.accepted = true;
            }

            Flickable {
                id: flick
                anchors.fill: parent
                contentHeight: body.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: body
                    width: card.width
                    spacing: 0

                    // ── header: title + tabs ──
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 14
                        Layout.bottomMargin: 10
                        spacing: 6
                        Text { text: "λ control"; color: Theme.ink; font.family: Theme.pixel; font.pixelSize: 24 }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: root.tabs
                            Btn {
                                required property var modelData
                                required property int index
                                text: (index + 1) + " " + modelData.id
                                hue: modelData.hue
                                nav: false
                                on: Ui.controlTab === modelData.id
                                onClicked: Ui.controlTab = modelData.id
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }

                    // ── AUDIO ──
                    ColumnLayout {
                        visible: Ui.controlTab === "audio"
                        Layout.fillWidth: true
                        Layout.margins: 14
                        spacing: 3

                        Label { text: "AUDIO // OUT" }
                        Level {
                            name: "vol"
                            hue: Theme.rose
                            value: Pipewire.defaultAudioSink?.audio?.volume ?? 0
                            muted: Pipewire.defaultAudioSink?.audio?.muted ?? false
                            onPicked: v => { if (Pipewire.defaultAudioSink?.audio) Pipewire.defaultAudioSink.audio.volume = v }
                            onToggleMute: { const a = Pipewire.defaultAudioSink?.audio; if (a) a.muted = !a.muted }
                        }
                        Repeater {
                            model: root.sinks
                            Row {
                                required property var modelData
                                navKey: "sink:" + modelData.id
                                name: root.label(modelData)
                                note: modelData === Pipewire.defaultAudioSink ? "default" : ""
                                current: modelData === Pipewire.defaultAudioSink
                                hue: current ? Theme.ink : Theme.muted
                                onClicked: Pipewire.preferredDefaultAudioSink = modelData
                            }
                        }

                        Label { text: "AUDIO // IN" }
                        Level {
                            name: "mic"
                            hue: Theme.aqua
                            value: Pipewire.defaultAudioSource?.audio?.volume ?? 0
                            muted: Pipewire.defaultAudioSource?.audio?.muted ?? false
                            onPicked: v => { if (Pipewire.defaultAudioSource?.audio) Pipewire.defaultAudioSource.audio.volume = v }
                            onToggleMute: { const a = Pipewire.defaultAudioSource?.audio; if (a) a.muted = !a.muted }
                        }
                        Repeater {
                            model: root.sources
                            Row {
                                required property var modelData
                                navKey: "source:" + modelData.id
                                name: root.label(modelData)
                                note: modelData === Pipewire.defaultAudioSource ? "default" : ""
                                current: modelData === Pipewire.defaultAudioSource
                                hue: current ? Theme.ink : Theme.muted
                                onClicked: Pipewire.preferredDefaultAudioSource = modelData
                            }
                        }

                        Label { text: "MIXER // APPS"; visible: root.streams.length > 0 }
                        Repeater {
                            model: root.streams
                            Level {
                                required property var modelData
                                navKey: "stream:" + modelData.id
                                name: root.appName(modelData).slice(0, 4)
                                hue: Theme.rose
                                value: modelData.audio?.volume ?? 0
                                muted: modelData.audio?.muted ?? false
                                onPicked: v => { if (modelData.audio) modelData.audio.volume = v }
                                onToggleMute: { if (modelData.audio) modelData.audio.muted = !modelData.audio.muted }
                            }
                        }
                        Mono { visible: root.streams.length === 0; text: "  nothing is playing sound"; color: Theme.faint; font.pixelSize: Theme.small; Layout.topMargin: 6 }
                    }

                    // ── NET ──
                    ColumnLayout {
                        visible: Ui.controlTab === "net"
                        Layout.fillWidth: true
                        Layout.margins: 14
                        spacing: 3

                        Label { text: "NET // WIRED"; visible: root.wired.length > 0 }
                        Repeater {
                            model: root.wired
                            Row {
                                required property var modelData
                                readonly property bool up: modelData.state === "connected"
                                navKey: "wired:" + modelData.dev
                                name: modelData.dev + (modelData.profile ? "  " + modelData.profile : "")
                                readonly property bool cable: modelData.state !== "unavailable"
                                note: cable ? modelData.state : "no cable"
                                current: up
                                hue: up ? Theme.ink : Theme.muted
                                action: !cable ? "" : up ? "disconnect" : "connect"
                                actionHue: up ? Theme.orange : Theme.blue
                                onClicked: if (cable) actionClicked()
                                onActionClicked: root.nmcli(["device", up ? "disconnect" : "connect", modelData.dev])
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.profiles.length > 0
                            Label { text: "NET // PROFILES · " + root.profiles.length }
                            Item { Layout.fillWidth: true }
                            Btn {
                                visible: root.cabled.length > 0
                                navKey: "btn:wired-target"
                                text: "on " + root.target + (root.cabled.length > 1 ? "  ⇄" : "")
                                hue: Theme.blue
                                onClicked: root.cycleTarget()
                            }
                        }
                        Repeater {
                            model: root.profiles
                            Row {
                                required property var modelData
                                readonly property bool missing: modelData.bound === "missing"
                                navKey: "profile:" + modelData.uuid
                                name: modelData.name
                                note: root.profileNote(modelData)
                                current: modelData.active !== ""
                                hue: current ? Theme.ink : missing ? Theme.faint : Theme.blue
                                onClicked: {
                                    if (missing && !current) root.netError = modelData.name + ": its adapter isn't plugged in";
                                    else if (root.wiredBusy === "") root.wiredProfile(modelData);
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "NET // WIFI" + (root.wifiDev ? "  " + root.wifiDev.name : "") }
                            Mono {
                                visible: root.wifiDev?.scannerEnabled ?? false
                                text: "scanning…"; color: Theme.faint; font.pixelSize: Theme.label
                                Layout.topMargin: 6; Layout.bottomMargin: 2
                            }
                            Item { Layout.fillWidth: true }
                            Btn {
                                text: Networking.wifiEnabled ? "wifi on" : "wifi off"
                                hue: Theme.blue
                                on: Networking.wifiEnabled
                                onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                            }
                            Btn { text: "settings"; hue: Theme.amber; onClicked: root.netSettings() }
                        }
                        Mono { visible: !root.wifiDev; text: "  no wifi device"; color: Theme.faint; font.pixelSize: Theme.small }
                        Repeater {
                            model: Networking.wifiEnabled ? root.wifiNets.slice(0, 12) : []
                            ColumnLayout {
                                id: wrow
                                required property var modelData
                                readonly property string ssid: modelData.name || "(hidden)"
                                readonly property bool open: modelData.security === WifiSecurityType.Open
                                readonly property bool busy: modelData.stateChanging || modelData.state === root.netState.Connecting
                                readonly property bool asking: root.pskFor !== "" && root.pskFor === modelData.name
                                Layout.fillWidth: true
                                spacing: 3

                                Connections {
                                    target: wrow.modelData
                                    ignoreUnknownSignals: true
                                    function onConnectionFailed(reason) { root.wifiFailed(wrow.modelData, wrow.ssid, wrow.open, reason) }
                                    function onNmReasonChanged() { root.wifiFailed(wrow.modelData, wrow.ssid, wrow.open, wrow.modelData.nmReason) }
                                    function onConnectedChanged() {
                                        if (wrow.modelData.connected && root.pskFor === wrow.modelData.name) root.pskFor = "";
                                        if (wrow.modelData.connected) root.netError = "";
                                    }
                                }

                                Row {
                                    navKey: "wifi:" + wrow.ssid
                                    name: wrow.ssid
                                    note: (wrow.busy ? "connecting…  " : wrow.modelData.connected ? "connected  " : wrow.modelData.known ? "known  " : "")
                                          + (wrow.open ? "open " : "") + root.signal(wrow.modelData.signalStrength)
                                    current: wrow.modelData.connected || wrow.asking
                                    hue: wrow.modelData.connected ? Theme.ink : wrow.modelData.known ? Theme.blue : Theme.muted
                                    action: wrow.modelData.known ? (root.armed === "wifi:" + wrow.ssid ? "sure?" : "forget") : ""
                                    // known and open networks connect right away; new secured ones ask below
                                    onClicked: {
                                        root.netError = "";
                                        if (wrow.modelData.connected) wrow.modelData.disconnect();
                                        else if (wrow.modelData.known || wrow.open) wrow.modelData.connect();
                                        else { root.pskText = ""; root.pskFor = wrow.asking ? "" : wrow.modelData.name; }
                                    }
                                    onActionClicked: { if (root.confirm("wifi:" + wrow.ssid)) wrow.modelData.forget() }
                                }
                                RowLayout {
                                    visible: wrow.asking
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 30
                                    Layout.bottomMargin: 4
                                    spacing: 6
                                    onVisibleChanged: if (visible) psk.focusIn()
                                    Mono { text: "λ psk >"; color: Theme.aqua }
                                    // the row is rebuilt as signals change; the typed text is kept in root
                                    Field {
                                        id: psk
                                        navKey: "psk:" + wrow.ssid
                                        text: root.pskText
                                        onTextChanged: root.pskText = text
                                        secret: !showPsk.on
                                        hue: Theme.blue
                                        placeholder: "password"
                                        onAccepted: if (text.length >= 8) { root.joinWithPsk(wrow.modelData, text); root.netError = "" }
                                                    else root.netError = "a wifi password has at least 8 characters"
                                        onCancelled: root.pskFor = ""
                                    }
                                    Btn { id: showPsk; text: "show"; hue: Theme.faint; on: root.pskShown; onClicked: root.pskShown = !root.pskShown }
                                    Btn { text: "join"; hue: Theme.blue; on: psk.text.length >= 8; onClicked: psk.accepted() }
                                }
                            }
                        }
                        Mono {
                            visible: root.netError !== ""
                            Layout.fillWidth: true
                            text: "[!!] " + root.netError
                            color: Theme.orange; font.pixelSize: Theme.small; wrapMode: Text.Wrap
                        }
                        Mono {
                            text: "⏎ / click: connect · profiles go to their own adapter, else [on …] · del: forget"
                            color: Theme.faint; font.pixelSize: Theme.label; Layout.topMargin: 6
                        }
                    }

                    // ── BT ──
                    ColumnLayout {
                        visible: Ui.controlTab === "bt"
                        Layout.fillWidth: true
                        Layout.margins: 14
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: "BT // " + (root.bt?.name ?? "no adapter") }
                            Item { Layout.fillWidth: true }
                            Btn {
                                visible: !!root.bt
                                text: root.bt?.enabled ? "bt on" : "bt off"
                                hue: Theme.cyan
                                on: root.bt?.enabled ?? false
                                onClicked: root.bt.enabled = !root.bt.enabled
                            }
                            Btn {
                                visible: root.bt?.enabled ?? false
                                text: root.bt?.discovering ? "scanning…" : "scan"
                                hue: Theme.blue
                                on: root.bt?.discovering ?? false
                                onClicked: root.bt.discovering = !root.bt.discovering
                            }
                        }
                        Repeater {
                            model: (root.bt?.enabled ?? false) ? root.btDevices.slice(0, 14) : []
                            Row {
                                id: brow
                                required property var modelData
                                readonly property bool connecting: modelData.state === BluetoothDeviceState.Connecting
                                navKey: "bt:" + modelData.address
                                Connections {
                                    target: brow.modelData
                                    // paired from here: trust it (reconnects by itself later) and connect
                                    function onPairedChanged() {
                                        if (brow.modelData.paired && root.pairingWith === brow.modelData.address) {
                                            root.pairingWith = "";
                                            brow.modelData.trusted = true;
                                            brow.modelData.connect();
                                        }
                                    }
                                }
                                name: modelData.name || modelData.address
                                note: (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%  " : "")
                                      + (modelData.connected ? "connected" : modelData.pairing ? "pairing…"
                                         : connecting ? "connecting…"
                                         : modelData.paired ? "paired" : "new")
                                current: modelData.connected
                                hue: modelData.connected ? Theme.ink : modelData.paired ? Theme.cyan : Theme.muted
                                action: modelData.pairing ? "cancel"
                                      : modelData.paired ? (root.armed === "bt:" + modelData.address ? "sure?" : "forget") : ""
                                onClicked: {
                                    if (modelData.connected) modelData.disconnect();
                                    else if (modelData.paired) modelData.connect();
                                    else if (!modelData.pairing) { root.pairingWith = modelData.address; modelData.pair(); }
                                }
                                onActionClicked: {
                                    if (modelData.pairing) modelData.cancelPair();
                                    else if (root.confirm("bt:" + modelData.address)) modelData.forget();
                                }
                            }
                        }
                        Mono {
                            visible: (root.bt?.enabled ?? false) && root.btDevices.length === 0
                            text: "  no devices · press scan"; color: Theme.faint; font.pixelSize: Theme.small
                        }
                        Mono {
                            text: "⏎ / click: connect / disconnect · del: forget · new devices pair and connect (scan first)"
                            color: Theme.faint; font.pixelSize: Theme.label; Layout.topMargin: 6
                        }
                    }

                    // ── NOOK: what the shell shows, homelab hosts, weather place ──
                    ColumnLayout {
                        id: nookTab
                        visible: Ui.controlTab === "nook"
                        Layout.fillWidth: true
                        Layout.margins: 14
                        spacing: 3

                        readonly property var hostRe: /^[A-Za-z0-9][A-Za-z0-9_.-]{0,252}(:\d{1,5})?$/
                        readonly property var nameRe: /^[A-Za-z0-9][A-Za-z0-9_.-]{0,31}$/
                        function addHost() {
                            const n = newName.text.trim(), h = newHost.text.trim();
                            if (!nookTab.nameRe.test(n)) { Feeds.confError = "name: letters, digits, '.', '_', '-' (no spaces)"; newName.focusIn(); return; }
                            if (!nookTab.hostRe.test(h)) { Feeds.confError = "host: an address or name, or host:port"; newHost.focusIn(); return; }
                            Feeds.setConf("srv", n, h);
                            Settings.set("widget.srv", true);
                            newName.text = ""; newHost.text = "";
                            newName.focusIn();
                        }

                        Label { text: "BAR // MODULES" }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 6
                            rowSpacing: 0
                            Repeater {
                                model: Settings.bar
                                Check {
                                    required property var modelData
                                    navKey: modelData.id
                                    name: modelData.name; note: modelData.note
                                    on: Settings.shown(modelData.id)
                                    hue: Theme.red
                                    onToggled: Settings.toggle(modelData.id)
                                }
                            }
                        }

                        Label { text: "DESK // WIDGETS" }
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 6
                            rowSpacing: 0
                            Repeater {
                                model: Settings.widgets.concat(Settings.desk)
                                Check {
                                    required property var modelData
                                    navKey: modelData.id
                                    name: modelData.name.toLowerCase(); note: modelData.note
                                    on: Settings.shown(modelData.id)
                                    hue: Theme.aqua
                                    onToggled: Settings.toggle(modelData.id)
                                }
                            }
                        }

                        Label { text: "SRV // HOMELAB · " + (Feeds.conf.srv ?? []).length }
                        Repeater {
                            model: Feeds.conf.srv ?? []
                            Row {
                                required property var modelData
                                navKey: "srv:" + modelData.name
                                readonly property var live: (Feeds.srv.hosts ?? []).find(h => h.name === modelData.name) ?? null
                                name: modelData.name
                                note: modelData.host + (live ? (live.up ? "  ● " + Math.round(live.ms) + "ms" : "  ● down") : "")
                                hue: live ? (live.up ? Theme.aqua : Theme.orange) : Theme.ink
                                action: root.armed === "srv:" + modelData.name ? "sure?" : "remove"
                                onClicked: { newName.text = modelData.name; newHost.text = modelData.host; newHost.focusIn() }
                                onActionClicked: { if (root.confirm("srv:" + modelData.name)) Feeds.unsetConf("srv", modelData.name) }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field { id: newName; placeholder: "name"; Layout.preferredWidth: 120; Layout.fillWidth: false; onAccepted: newHost.focusIn(); onCancelled: text = "" }
                            Field { id: newHost; placeholder: "host  or  host:port"; onAccepted: nookTab.addHost(); onCancelled: text = "" }
                            Btn { text: (Feeds.conf.srv ?? []).some(h => h.name === newName.text.trim()) ? "save" : "add"; hue: Theme.aqua; onClicked: nookTab.addHost() }
                        }

                        Label { text: "WX // PLACE" }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Field {
                                id: place
                                text: Feeds.conf.weather?.location ?? ""
                                placeholder: "city, ~landmark or airport · empty = by IP"
                                hue: Theme.gold
                                onAccepted: Feeds.setConf("weather", "location", text.trim())
                                onCancelled: text = Feeds.conf.weather?.location ?? ""
                            }
                            Btn { text: "set"; hue: Theme.gold; onClicked: place.accepted() }
                        }

                        Mono {
                            visible: Feeds.confError !== ""
                            Layout.fillWidth: true
                            text: "[!!] " + Feeds.confError
                            color: Theme.orange; font.pixelSize: Theme.small; wrapMode: Text.Wrap
                        }
                        Mono {
                            Layout.fillWidth: true
                            text: "⏎ / click: on / off · a host row fills the form, del removes it · kept in ~/.config/nook/shell.json and " + (Feeds.conf.path ?? "widgets.conf")
                            color: Theme.faint; font.pixelSize: Theme.label; Layout.topMargin: 6; wrapMode: Text.Wrap
                        }
                    }

                    // ── APPS: background apps (tray) + media ──
                    ColumnLayout {
                        visible: Ui.controlTab === "apps"
                        Layout.fillWidth: true
                        Layout.margins: 14
                        spacing: 3

                        Label { text: "APPS // BACKGROUND · " + SystemTray.items.values.length }
                        Repeater {
                            model: SystemTray.items
                            Rectangle {
                                id: trow
                                required property var modelData
                                required property int index
                                readonly property string navKey: "tray:" + modelData.id
                                function openMenu(x, y) {
                                    const p = trow.mapToItem(null, x, y);
                                    trow.modelData.display(panel, p.x, p.y);
                                }
                                function run() {
                                    if (trow.modelData.onlyMenu || root.trayMenuOnly.includes(trow.modelData.id)) { trow.openMenu(30, trow.height); return; }
                                    trow.modelData.activate();
                                    Ui.controlOpen = false;
                                }
                                // ⏎ opens the app, m / menu key its menu
                                activeFocusOnTab: true
                                onActiveFocusChanged: if (activeFocus) root.focused(trow)
                                Component.onCompleted: root.restore(trow)
                                Keys.onPressed: e => {
                                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) trow.run();
                                    else if (e.key === Qt.Key_M || e.key === Qt.Key_Menu) trow.openMenu(30, trow.height);
                                    else return;
                                    e.accepted = true;
                                }
                                Layout.fillWidth: true
                                implicitHeight: 26
                                radius: Theme.radiusSm
                                color: tArea.containsMouse || activeFocus ? Theme.bg300 : "transparent"
                                border.width: activeFocus ? 2 : 0
                                border.color: Theme.cyan
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    spacing: 8
                                    Mono { text: "[" + String(trow.index + 1).padStart(2, "0") + "]"; color: Theme.faint }
                                    IconImage { source: trow.modelData.icon; implicitSize: 16 }
                                    Mono {
                                        text: (trow.modelData.title || trow.modelData.tooltipTitle || trow.modelData.id).toLowerCase()
                                        color: Theme.amber
                                        Layout.maximumWidth: 200
                                    }
                                    Mono { text: ".".repeat(80); color: Theme.faint; Layout.fillWidth: true; clip: true; elide: Text.ElideNone }
                                    Mono { text: trow.modelData.status === Status.NeedsAttention ? "needs you" : trow.modelData.id.toLowerCase(); color: trow.modelData.status === Status.NeedsAttention ? Theme.orange : Theme.muted; font.pixelSize: Theme.small; Layout.maximumWidth: 120 }
                                }
                                MouseArea {
                                    id: tArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: m => m.button === Qt.RightButton ? trow.openMenu(m.x, m.y) : trow.run()
                                }
                            }
                        }
                        Mono { visible: SystemTray.items.values.length === 0; text: "  nothing running in the background"; color: Theme.faint; font.pixelSize: Theme.small }

                        Label { text: "MEDIA // NOW"; visible: root.player !== null }
                        ColumnLayout {
                            visible: root.player !== null
                            Layout.fillWidth: true
                            spacing: 2
                            Mono { text: root.player?.trackTitle ?? ""; color: Theme.ink; font.bold: true; Layout.fillWidth: true }
                            Mono { text: (root.player?.trackArtist ?? "") + "  ·  " + (root.player?.identity ?? "").toLowerCase(); color: Theme.muted; Layout.fillWidth: true }
                            RowLayout {
                                spacing: 6
                                Btn { text: "◀◀"; hue: Theme.rose; onClicked: root.player?.previous() }
                                Btn { text: root.player?.isPlaying ? "▮▮" : "▶"; hue: Theme.rose; on: root.player?.isPlaying ?? false; onClicked: root.player?.togglePlaying() }
                                Btn { text: "▶▶"; hue: Theme.rose; onClicked: root.player?.next() }
                            }
                        }
                        Mono {
                            text: "⏎ / click: open · m / right-click: its menu"
                            color: Theme.faint; font.pixelSize: Theme.label; Layout.topMargin: 6
                        }
                    }

                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }
                    Mono {
                        Layout.margins: 10
                        Layout.leftMargin: 14
                        text: "↑↓ move · ⏎ press · ←→ level · del forget · tab / 1‥5 tabs · esc · SUPER A / N / ⇧B"
                        color: Theme.faint; font.pixelSize: Theme.label
                    }
                }
            }
        }
    }
}
