// The bar: a 30px strip flush on the bottom edge, its modules as pills inside it.
//   λ nook · workspaces · window title ··························· cpu/ram · ● clock · date ▮▮▮▯ · power
// The clock pill is also the control center's button: sound, net, bluetooth, the tray apps and the
// nook tab sit behind it (ControlCenter.qml).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Scope {
    id: root

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // ── keyboard layout (eu / de). Hyprland 0.57 sends no event for switchxkblayout, so the
    //    switch (pill click or SUPER K) asks for a re-read over IPC; a slow poll catches the rest ──
    property string kb: ""
    function kbShort(name) {
        if (/eurkey/i.test(name)) return "eu";
        if (/german|deutsch/i.test(name)) return "de";
        return name.slice(0, 2).toLowerCase();
    }
    function switchKb() { Quickshell.execDetached(["sh", "-c", "hyprctl switchxkblayout all next >/dev/null && qs -c nook ipc call kb refresh"]) }
    IpcHandler {
        target: "kb"
        function refresh(): void { kbRead.running = true }
    }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: kbRead.running = true }
    Process {
        id: kbRead
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const k = JSON.parse(this.text).keyboards;
                    const main = k.find(x => x.main) ?? k[0];
                    if (main) root.kb = root.kbShort(main.active_keymap);
                } catch (e) {}
            }
        }
    }
    Connections {
        target: Hyprland
        // data: "<keyboard>,<layout name>"
        function onRawEvent(event) {
            if (event.name === "activelayout") root.kb = root.kbShort(event.data.split(",").slice(1).join(","));
        }
    }
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    // ── battery, for the clock's overview ──
    readonly property var batt: UPower.displayDevice
    readonly property bool hasBatt: batt.isLaptopBattery
    readonly property real pct: batt.percentage > 1 ? batt.percentage / 100 : batt.percentage
    readonly property bool charging: batt.state === UPowerDeviceState.Charging || batt.state === UPowerDeviceState.FullyCharged
    readonly property color battHue: charging ? Theme.aqua : pct <= 0.15 ? Theme.orange : pct <= 0.3 ? Theme.gold : Theme.ink
    readonly property color kbHue: kb === "de" ? Theme.gold : Theme.aqua

    // Hyprland 0.57 takes Lua dispatchers over IPC
    function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }
    function openMenu() { Ui.toggleLauncher() }

    // one bar module: bg-100 at 88%, 1px line, radius-md
    component Pill: Rectangle {
        id: pill
        default property alias content: row.data
        property bool hot: false                       // cyan ring + glow (menu open, hover)
        signal clicked(var mouse)
        signal scrolled(var wheel)
        implicitHeight: Theme.pill
        implicitWidth: row.implicitWidth + 20
        radius: Theme.radius
        color: Theme.alpha(Theme.bg100, 0.88)
        border.width: 1
        border.color: hot || area.containsMouse ? Theme.cyan : Theme.line
        Behavior on border.color { ColorAnimation { duration: 120 } }
        // declared before the row so mouse areas inside the module (workspace marks, tray icons) sit on top
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: m => pill.clicked(m)
            onWheel: w => pill.scrolled(w)
        }
        RowLayout { id: row; anchors.centerIn: parent; spacing: 10 }
    }
    component Label: Text {
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.small
    }
    // coloured text gets a soft halo in its own colour
    component Glow: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.8
        shadowOpacity: 0.8
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 0
    }
    // neon text: two blurred copies of the text under a crisp one. A single shadow (Glow) is too
    // faint on thin glyphs; stacking the blur makes the halo read at bar size.
    component Neon: Item {
        id: neon
        property alias text: crisp.text
        property alias color: crisp.color
        property alias font: crisp.font
        property real glow: 0.9                    // halo strength, 0–1
        implicitWidth: crisp.implicitWidth
        implicitHeight: crisp.implicitHeight
        Text { id: src; visible: false; layer.enabled: true; text: crisp.text; color: crisp.color; font: crisp.font }
        Repeater {
            model: 2
            MultiEffect {
                source: src
                anchors.fill: src
                autoPaddingEnabled: true
                blurEnabled: true
                blur: 1.0
                blurMax: 10
                opacity: neon.glow
            }
        }
        Text { id: crisp; font.family: Theme.font; font.pixelSize: Theme.small; color: Theme.muted }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            readonly property var hmon: Hyprland.monitorFor(modelData)
            screen: modelData
            WlrLayershell.namespace: "nook-bar"
            anchors { bottom: true; left: true; right: true }
            implicitHeight: Theme.bar
            // exactly the strip: Hyprland adds gaps_out (6) on top, so windows end 6 px above it,
            // the same as the gap between two windows. (Hyprland counts a layer's margin into its
            // exclusive zone, so a margin here would have to come off this number.)
            exclusiveZone: Theme.bar
            color: "transparent"

            // the strip: bg-100 at 88% with a hairline on top
            Rectangle {
                anchors.fill: parent
                color: Theme.alpha(Theme.bg100, 0.88)
                Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right } height: 1; color: Theme.line }
            }

            // ── overflow: the right side (cpu/ram, clock, power) gets at most half the bar ──
            // left:  start + workspaces stay; the window tag takes the rest (title first, then
            //        the whole tag, go when there's no room)
            // right: cpu/ram goes when it doesn't fit
            // Modules switched off in the nook tab (Settings) take no room.
            function room(p) { return p.visible ? p.implicitWidth + Theme.gap : 0 }
            readonly property real half: width / 2 - Theme.gap
            readonly property real tagRoom: width - room(startPill) - room(wsPill) - room(clockPill) - room(powerPill)
                                            - (showCpu ? room(cpuPill) : 0) - 2 * Theme.gap
            readonly property real tagFixed: 20 + 4 * 10 + lb.implicitWidth + appLbl.implicitWidth + dash.implicitWidth + rb.implicitWidth
            readonly property real titleRoom: Math.min(320, tagRoom - tagFixed)
            readonly property bool showCpu: room(clockPill) + room(powerPill) + cpuPill.implicitWidth <= half

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.edge
                anchors.rightMargin: Theme.edge
                anchors.topMargin: 1          // below the hairline
                spacing: Theme.gap

                // ── λ nook: solid red neon, opens the hack menu (right-click: the nook tab) ──
                Pill {
                    id: startPill
                    visible: Settings.shown("bar.start")
                    color: Theme.red
                    border.color: Ui.launcherOpen || (Ui.controlOpen && Ui.controlTab === "nook") ? Theme.cyan : Theme.red
                    border.width: Ui.launcherOpen || (Ui.controlOpen && Ui.controlTab === "nook") ? 2 : 1
                    // right-click: the nook tab, to pick what the bar and the desktop show
                    onClicked: m => m.button === Qt.RightButton ? Ui.openControl("nook") : root.openMenu()
                    layer.enabled: true
                    layer.effect: Glow { shadowColor: Theme.red; shadowBlur: 0.8; shadowOpacity: 0.7 }
                    Text { text: "λ"; color: Theme.onAccent; font.family: Theme.pixel; font.pixelSize: 20 }
                    Text { text: "nook"; color: Theme.onAccent; font.family: Theme.font; font.pixelSize: Theme.body; font.bold: true }
                }

                // ── workspaces 1–9: on this screen = cyan bar, occupied = muted, empty = faint,
                //    urgent = orange. Click brings it to this screen (trades if the other one shows it) ──
                Pill {
                    id: wsPill
                    visible: Settings.shown("bar.workspaces")
                    Repeater {
                        model: 9
                        Item {
                            id: mark
                            required property int index
                            readonly property int ws: index + 1
                            readonly property var wsObj: Hyprland.workspaces.values.find(w => w.id === ws) ?? null
                            readonly property bool active: bar.hmon?.activeWorkspace?.id === ws
                            readonly property bool urgent: wsObj?.urgent ?? false
                            implicitWidth: dot.width
                            implicitHeight: 14
                            Rectangle {
                                id: dot
                                anchors.verticalCenter: parent.verticalCenter
                                width: mark.active ? 30 : 10
                                height: 10
                                radius: Theme.radiusSm
                                color: mark.urgent ? Theme.orange : mark.active ? Theme.cyan
                                     : mark.wsObj ? Theme.muted : Theme.faint
                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on color { ColorAnimation { duration: 180 } }
                                layer.enabled: mark.active || mark.urgent
                                layer.effect: Glow { shadowColor: dot.color }
                            }
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                onClicked: root.dispatch(`function() nook_show_workspace(${mark.ws}, "${bar.hmon?.name ?? ""}") end`)
                            }
                        }
                    }
                }

                // ── focused window as a tag ──
                Pill {
                    id: titlePill
                    visible: Settings.shown("bar.title") && (ToplevelManager.activeToplevel?.title ?? "") !== ""
                             && bar.tagRoom >= bar.tagFixed - dash.implicitWidth - 10
                    Label { id: lb; text: "["; color: Theme.faint }
                    Neon {
                        id: appLbl
                        // "org.kde.dolphin" → dolphin, Chromium web apps "brave-<32 letters>-default" → brave app
                        text: (ToplevelManager.activeToplevel?.appId ?? "").replace(/^(\w+)-[a-p]{32}-\w+$/, "$1 app").split(".").pop().toLowerCase()
                        color: Theme.cyan
                    }
                    Label { id: dash; text: "—"; color: Theme.faint; visible: bar.titleRoom >= 40 }
                    Label {
                        text: ToplevelManager.activeToplevel?.title ?? ""
                        color: Theme.ink
                        elide: Text.ElideRight
                        visible: bar.titleRoom >= 40
                        Layout.maximumWidth: Math.max(40, bar.titleRoom)
                    }
                    Label { id: rb; text: "]"; color: Theme.faint }
                }

                Item { Layout.fillWidth: true }

                // ── cpu sparkline + ram (first to go when the right side is full) ──
                Pill {
                    id: cpuPill
                    visible: Settings.shown("bar.cpu") && bar.showCpu
                    Label { text: "cpu" }
                    Neon { text: Stats.spark(Stats.cpuHist, 100); color: Theme.amber; font.pixelSize: 13 }
                    Neon { text: Stats.cpu + "%"; color: Theme.amber }
                    Label { text: "ram"; Layout.leftMargin: 4 }
                    Neon { text: Stats.ram + "%"; color: Theme.aqua }
                }

                // ── clock: the overview and the control center's button. kb dot · VT323 time · date ·
                //    battery bar. Click = control center (SUPER A), right-click = next layout (SUPER K),
                //    middle-click = mute, scroll = volume ±5%. Cyan ring + glow while the panel is open. ──
                Pill {
                    id: clockPill
                    visible: Settings.shown("bar.clock")
                    readonly property var sink: Pipewire.defaultAudioSink
                    readonly property bool attention: SystemTray.items.values.some(i => i.status === Status.NeedsAttention)
                    hot: Ui.controlOpen
                    border.width: hot ? 2 : 1
                    onClicked: m => {
                        if (m.button === Qt.RightButton) root.switchKb();
                        else if (m.button === Qt.MiddleButton) { if (sink?.audio) sink.audio.muted = !sink.audio.muted }
                        else Ui.toggleControl();
                    }
                    onScrolled: w => { if (sink?.audio) sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + (w.angleDelta.y > 0 ? 0.05 : -0.05))) }
                    layer.enabled: hot
                    layer.effect: Glow { shadowColor: Theme.cyan; shadowBlur: 0.9; shadowOpacity: 0.6 }
                    // keyboard layout: a glowing dot, aqua = eu, gold = de; click switches (like SUPER K)
                    Item {
                        visible: root.kb !== ""
                        implicitWidth: 10; implicitHeight: 10
                        Rectangle {
                            id: kbDot
                            anchors.centerIn: parent
                            width: 8; height: 8; radius: 4
                            color: root.kbHue
                            Behavior on color { ColorAnimation { duration: 200 } }
                            layer.enabled: true
                            layer.effect: Glow { shadowColor: kbDot.color; shadowBlur: 1.0; shadowOpacity: 0.9 }
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.switchKb() }
                    }
                    Neon {
                        id: hhmm
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: Theme.red
                        font.family: Theme.pixel
                        font.pixelSize: 22
                        glow: 1.0
                    }
                    Rectangle { implicitWidth: 1; implicitHeight: 14; color: Theme.line }
                    Label {
                        // a plain date: "sa 07.11.2026" (weekday in the system language)
                        text: Qt.locale().toString(clock.date, "ddd dd.MM.yyyy").replace(/^(\S+?)\.? /, "$1 ").toLowerCase()
                        color: Theme.ink
                        font.pixelSize: Theme.body
                    }
                    // battery: a thin bar in its state's hue (aqua charging, gold ≤ 30 %, orange ≤ 15 %)
                    Rectangle { visible: root.hasBatt; implicitWidth: 1; implicitHeight: 14; color: Theme.line }
                    RowLayout {
                        visible: root.hasBatt
                        spacing: 6
                        Rectangle {
                            implicitWidth: 46; implicitHeight: 8
                            radius: Theme.radiusSm
                            color: Theme.bg300
                            border.width: 1
                            border.color: Theme.alpha(root.battHue, 0.45)
                            Rectangle {
                                id: battFill
                                x: 1; y: 1
                                height: parent.height - 2
                                width: Math.max(2, (parent.width - 2) * Math.max(0, Math.min(1, root.pct)))
                                radius: 1
                                color: root.battHue
                                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                layer.enabled: true
                                layer.effect: Glow { shadowColor: battFill.color }
                                // charging: a slow pulse
                                SequentialAnimation on opacity {
                                    running: root.charging && root.pct < 1
                                    loops: Animation.Infinite
                                    onRunningChanged: if (!running) battFill.opacity = 1
                                    NumberAnimation { to: 0.55; duration: 900; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                        Neon { text: Math.round(root.pct * 100) + "%"; color: root.battHue }
                    }
                    // muted, or a tray app asking for you: one small mark, details in the panel
                    Label { visible: clockPill.sink?.audio?.muted ?? false; text: "mute"; color: Theme.faint }
                    Neon { visible: clockPill.attention; text: "●"; color: Theme.orange }
                }

                // ── power: solid red like λ nook; opens the menu (power buttons), right-click locks ──
                Pill {
                    id: powerPill
                    visible: Settings.shown("bar.power")
                    color: Theme.red
                    border.color: Ui.launcherOpen ? Theme.cyan : Theme.red
                    border.width: Ui.launcherOpen ? 2 : 1
                    onClicked: m => m.button === Qt.RightButton
                        ? Quickshell.execDetached(["loginctl", "lock-session"])
                        : root.openMenu()
                    layer.enabled: true
                    layer.effect: Glow { shadowColor: Theme.red; shadowBlur: 0.8; shadowOpacity: 0.7 }
                    Text { text: "⏻"; color: Theme.onAccent; font.pixelSize: 14; font.bold: true }
                }
            }

        }
    }
}
