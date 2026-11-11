// Keybind cheatsheet, two ways:
//   SUPER / (ipc: cheatsheet peek)   over every window on the focused screen; any key or click closes it
//   on the wallpaper                 under every window, on any empty workspace; switched in the nook
//                                    tab (ipc: cheatsheet toggle), kept in shell.json
//
// The binds are NOT listed here: they come from `hyprctl binds -j`. Every bind in
// hypr/nook.lua with a description "group: label" shows up, grouped and coloured.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Scope {
    id: root
    readonly property bool shown: Settings.shown("desk.cheatsheet")
    property bool peek: false
    property var groups: []

    // two columns, filled row by row: apps | settings, windows | workspaces, system
    readonly property var order: ["apps", "settings", "windows", "workspaces", "system"]
    readonly property var hues: ({ apps: Theme.amber, settings: Theme.aqua, windows: Theme.cyan, workspaces: Theme.blue, system: Theme.red })

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { Settings.toggle("desk.cheatsheet") }
        function peek(): void { if (!root.peek) binds.running = true; root.peek = !root.peek }
        function reload(): void { binds.running = true }
    }

    // modmask bits → key cap names
    function mods(m) {
        const names = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "⇧"]];
        return names.filter(n => m & n[0]).map(n => n[1]);
    }
    function keyName(k) {
        const map = { "RETURN": "⏎", "Return": "⏎", "SPACE": "SPACE", "space": "SPACE", "slash": "/",
                      "left": "←", "right": "→", "up": "↑", "down": "↓", "PRINT": "PRINT", "Print": "PRINT",
                      "mouse:272": "LMB drag", "mouse:273": "RMB drag", "mouse_down": "scroll", "mouse_up": "scroll" };
        return map[k] ?? k.toUpperCase();
    }

    // collapse "focus ←" … "focus ↓" into one row "SUPER ←↑→↓  focus", same for 1‥9
    function build(list) {
        const rows = {};
        for (const b of list) {
            const d = b.description ?? "";
            const i = d.indexOf(":");
            if (i < 0) continue;
            const g = d.slice(0, i).trim(), label = d.slice(i + 1).trim();
            if (!rows[g]) rows[g] = [];
            let keys = root.mods(b.modmask).concat([root.keyName(b.key)]);
            let lab = label;
            let m;
            if ((m = label.match(/^(.*) ([←↑→↓])$/))) { lab = m[1]; keys[keys.length - 1] = "←↑→↓"; }
            else if ((m = label.match(/^(.*) (\d)$/))) { lab = m[1].replace(/ to$/, ""); keys[keys.length - 1] = "1‥9"; }
            else if (label.endsWith("(scroll)")) { lab = "cycle workspaces"; }
            const id = keys.join(" ") + "|" + lab;
            if (!rows[g].some(r => r.id === id)) rows[g].push({ id, keys, label: lab });
        }
        const known = root.order.filter(g => rows[g]);
        const extra = Object.keys(rows).filter(g => !root.order.includes(g));
        root.groups = known.concat(extra).map(g => ({ name: g.toUpperCase(), hue: root.hues[g] ?? Theme.aqua, rows: rows[g] }));
    }

    Process {
        id: binds
        command: ["hyprctl", "binds", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { try { root.build(JSON.parse(this.text)); } catch (e) { root.groups = []; } }
        }
    }
    // pick up edits to nook.lua (Hyprland reloads it on save)
    Timer { interval: 15000; running: root.shown; repeat: true; onTriggered: binds.running = true }

    // a key cap: radius-sm, 1px border and 10% tint in the group hue
    component Cap: Rectangle {
        property alias text: t.text
        property color hue: Theme.cyan
        implicitWidth: t.implicitWidth + 10
        implicitHeight: 18
        radius: Theme.radiusSm
        color: Theme.alpha(hue, 0.10)
        border.width: 1
        border.color: Theme.alpha(hue, 0.55)
        Text { id: t; anchors.centerIn: parent; color: parent.hue; font.family: Theme.font; font.pixelSize: Theme.label; font.bold: true }
    }

    component Sheet: Rectangle {
        id: sheet
        property bool solid: false
        implicitHeight: body.implicitHeight + 36
        radius: Theme.radius
        color: Theme.alpha(Theme.bg000, solid ? 0.94 : 0.55)
        border.color: Theme.line
        border.width: 1

        ColumnLayout {
            id: body
            anchors { fill: parent; margins: 18 }
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text { text: "λ keybinds"; color: Theme.ink; font.family: Theme.pixel; font.pixelSize: 32 }
                Item { Layout.fillWidth: true }
                Text { text: "╭─[ hyprland // cheatsheet ]─╮"; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.small }
            }

            GridLayout {
                columns: 2
                columnSpacing: 28
                rowSpacing: 16
                Layout.fillWidth: true
                Repeater {
                    model: root.groups
                    ColumnLayout {
                        id: grp
                        required property var modelData
                        Layout.alignment: Qt.AlignTop
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 5
                        Text {
                            text: grp.modelData.name
                            color: grp.modelData.hue
                            font.family: Theme.font; font.pixelSize: Theme.label; font.bold: true
                            font.letterSpacing: 1.2
                        }
                        Repeater {
                            model: grp.modelData.rows
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: modelData.keys
                                    Cap { required property var modelData; text: modelData; hue: grp.modelData.hue }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.label
                                    color: Theme.muted
                                    elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: Theme.small
                                }
                            }
                        }
                    }
                }
            }

            Text {
                text: sheet.solid ? "from hypr/nook.lua · ⇧ = SHIFT · any key closes"
                                      : "from hypr/nook.lua · ⇧ = SHIFT · SUPER / shows it over the windows"
                color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.label
            }
        }
    }

    // on the wallpaper, every screen
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            readonly property bool portrait: modelData.height > modelData.width
            visible: root.shown && root.groups.length > 0
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "nook-cheatsheet"
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true }
            margins { top: 48; left: 56 }
            implicitWidth: portrait ? 560 : 640
            implicitHeight: wsheet.implicitHeight
            color: "transparent"
            Sheet { id: wsheet; anchors.fill: parent }
        }
    }

    // SUPER /: over every window on the focused screen, until a key or a click
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: over
            required property var modelData
            screen: modelData
            readonly property bool portrait: modelData.height > modelData.width
            visible: root.peek && root.groups.length > 0 && Hyprland.focusedMonitor?.name === modelData.name
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "nook-cheatsheet"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Theme.alpha(Theme.bg000, 0.35)
            MouseArea { anchors.fill: parent; onClicked: root.peek = false }
            Item {
                anchors.fill: parent
                focus: over.visible
                Keys.onPressed: e => { root.peek = false; e.accepted = true }
            }
            Sheet {
                solid: true
                anchors.centerIn: parent
                width: over.portrait ? 560 : 640
                height: implicitHeight
            }
        }
    }
}
