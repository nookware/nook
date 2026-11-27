// Screen picker, like Win+P: duplicate, extend, or only one screen. bin/nook-display does the work.
//   pops up by itself when a screen machine.lua doesn't know is plugged in (a beamer, a TV):
//     Hyprland → nook-display plugged → qs -c nook ipc call screens offer HDMI-A-1
//   SUPER ⇧ P (ipc: screens open) opens it any time; pressed again while open it moves down
//   1‥9 or ↑↓ / j k + ⏎ pick, esc keeps the screens as they are. Unplugging the beamer goes back
//   to extend by itself (nook-display unplugged).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

Scope {
    id: root
    property bool open: false
    property string fresh: ""        // the screen that was just plugged in, "" when opened by hand
    property var mons: []            // hyprctl monitors all -j
    property int sel: 0

    readonly property string here: Hyprland.focusedMonitor?.name ?? ""
    function mon(name) { return root.mons.find(m => m.name === name) }
    function label(m) {
        if (!m) return "";
        // "Samsung Electric Company LS27FG53x H9DY901150" → "Samsung LS27FG53x": make + model, no serial
        const w = (m.description || "").split(" ").filter(x => x);
        if (w.length >= 3) return w[0] + " " + w[w.length - 2];
        return w.join(" ");
    }
    function size(m) {
        if (!m) return "";
        const best = (m.availableModes || []).map(s => s.split("@")[0]).sort((a, b) => {
            const [aw, ah] = a.split("x").map(Number), [bw, bh] = b.split("x").map(Number);
            return bw * bh - aw * ah;
        })[0];
        return (best || `${m.width}x${m.height}`).replace("x", "×");
    }
    // what is on right now
    readonly property string current: {
        if (root.mons.some(m => m.mirrorOf && m.mirrorOf !== "none")) return "duplicate";
        const on = root.mons.filter(m => !m.disabled);
        if (on.length < root.mons.length && on.length === 1) return "only " + on[0].name;
        return "extend";
    }
    readonly property var options: {
        const list = [
            { id: "duplicate", key: "duplicate", hue: Theme.cyan,
              text: "every screen shows " + (root.here || "this one"), args: ["duplicate"] },
            { id: "extend", key: "extend", hue: Theme.aqua,
              text: "side by side, as in machine.lua", args: ["extend"] }
        ];
        // "only" rows: the new screen first, then this one, then the rest
        const names = root.mons.map(m => m.name);
        const order = [root.fresh, root.here].filter(n => n && names.includes(n))
                      .concat(names.filter(n => n !== root.fresh && n !== root.here));
        for (const n of [...new Set(order)]) {
            const m = root.mon(n);
            const who = n === root.fresh ? "the new screen · " : n === root.here ? "this screen · " : "";
            list.push({ id: "only " + n, key: "only " + n, hue: n === root.fresh ? Theme.gold : Theme.blue,
                        text: [who + n, root.label(m), root.size(m)].filter(x => x).join(" · ") + ", the others off", args: ["only", n] });
        }
        return list;
    }

    function show(name) {
        root.fresh = name || "";
        root.sel = 0;
        monsProc.running = true;
        root.open = true;
    }
    function pick(i) {
        const o = root.options[i];
        if (!o) return;
        root.open = false;
        Quickshell.execDetached(["nook-display"].concat(o.args));
    }

    IpcHandler {
        target: "screens"
        function offer(name: string): void { root.show(name) }
        // SUPER ⇧ P: open, or move down while open (like Win+P)
        function open(): void {
            if (root.open) root.sel = (root.sel + 1) % root.options.length;
            else root.show("");
        }
        function close(): void { root.open = false }
        function gone(): void { if (root.fresh && !root.mons.some(m => m.name === root.fresh)) root.open = false; monsProc.running = true }
    }

    Process {
        id: monsProc
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.mons = JSON.parse(this.text); } catch (e) { root.mons = []; }
                if (root.fresh && !root.mons.some(m => m.name === root.fresh)) root.open = false;
            }
        }
    }

    component Cap: Rectangle {
        property alias text: t.text
        property color hue: Theme.cyan
        implicitWidth: Math.max(18, t.implicitWidth + 10)
        implicitHeight: 18
        radius: Theme.radiusSm
        color: Theme.alpha(hue, 0.10)
        border.width: 1
        border.color: Theme.alpha(hue, 0.55)
        Text { id: t; anchors.centerIn: parent; color: parent.hue; font.family: Theme.font; font.pixelSize: Theme.label; font.bold: true }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.open && root.here === modelData.name
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "nook-screens"
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Theme.alpha(Theme.bg000, 0.35)
            MouseArea { anchors.fill: parent; onClicked: root.open = false }

            Item {
                anchors.fill: parent
                focus: win.visible
                Keys.onPressed: e => {
                    const n = root.options.length;
                    if (e.key === Qt.Key_Escape) root.open = false;
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_J || e.key === Qt.Key_Tab || e.key === Qt.Key_P) root.sel = (root.sel + 1) % n;
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_K || e.key === Qt.Key_Backtab) root.sel = (root.sel + n - 1) % n;
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.pick(root.sel);
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) root.pick(e.key - Qt.Key_1);
                    e.accepted = true;
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: 660
                height: body.implicitHeight + 36
                radius: Theme.radius
                color: Theme.alpha(Theme.bg000, 0.94)
                border.color: root.fresh ? Theme.gold : Theme.line
                border.width: 1
                MouseArea { anchors.fill: parent }   // clicks on the panel don't close it

                ColumnLayout {
                    id: body
                    anchors { fill: parent; margins: 18 }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "λ screens"; color: Theme.ink; font.family: Theme.pixel; font.pixelSize: 32 }
                        Item { Layout.fillWidth: true }
                        Text { text: "╭─[ now: " + root.current + " ]─╮"; color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.small }
                    }

                    // the screen that was just plugged in
                    RowLayout {
                        visible: root.fresh !== ""
                        Layout.fillWidth: true
                        spacing: 10
                        Text { text: "new screen"; color: Theme.gold; font.family: Theme.font; font.pixelSize: Theme.body; font.bold: true }
                        Text { text: root.fresh; color: Theme.ink; font.family: Theme.font; font.pixelSize: Theme.body }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: [root.label(root.mon(root.fresh)), root.size(root.mon(root.fresh))].filter(x => x).join(" · ")
                            color: Theme.muted; font.family: Theme.font; font.pixelSize: Theme.body
                        }
                    }

                    Repeater {
                        model: root.options
                        Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool active: index === root.sel
                            Layout.fillWidth: true
                            implicitHeight: 34
                            radius: Theme.radiusSm
                            color: active ? Theme.alpha(modelData.hue, 0.16) : "transparent"
                            border.width: active ? 1 : 0
                            border.color: Theme.alpha(modelData.hue, 0.7)
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                spacing: 10
                                Cap { text: String(row.index + 1); hue: row.modelData.hue }
                                Text {
                                    text: row.modelData.key.split(" ")[0]
                                    color: row.modelData.hue
                                    font.family: Theme.font; font.pixelSize: Theme.body; font.bold: true
                                    Layout.preferredWidth: 86
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.text
                                    color: row.active ? Theme.ink : Theme.muted
                                    elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: Theme.small
                                }
                                Text {
                                    visible: row.modelData.id === root.current
                                    text: "● now"
                                    color: Theme.faint
                                    font.family: Theme.font; font.pixelSize: Theme.label
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: root.sel = row.index
                                onClicked: root.pick(row.index)
                            }
                        }
                    }

                    Text {
                        text: "1‥9 / ↑↓ ⏎ pick · SUPER ⇧ P again moves down · esc keeps it · unplugging goes back to extend"
                        color: Theme.faint; font.family: Theme.font; font.pixelSize: Theme.label
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
