// The hack menu (SUPER SPACE, or the λ nook button): the design system's Launcher, live.
//
//   ┌ NOOK banner (fire → ice, diagonal) ─────────────────────────────┐
//   │ user@host  kernel  uptime  ● status                              │
//   │ λ ~/ > query▮                                                    │
//   │ APPS // PINNED | MATCH              │ SYS // LIVE  bars, net     │
//   │ [01] ▢ terminal ........... kitty   │ hexdump of what you type   │
//   │ …                                   │ the cat                    │
//   │ [ lock ] [ sleep ] [ reboot ] [ shutdown ]        ↑↓ nav · ⏎ run │
//   └──────────────────────────────────────────────────────────────────┘
//
// Keyboard only, the focus never leaves the prompt:
//   apps:  ↑↓ (ctrl n / p) move through every result, the list scrolls · pgup pgdn ±9 ·
//          ⏎ run · alt 1‥9 run a visible row · tab → power · esc close
//   power: ←→ ↑↓ pick · ⏎ / space press (reboot / shutdown ask with a second ⏎) ·
//          tab or esc → apps · typing goes back to the apps and searches
//   from anywhere: alt l lock · alt s sleep · alt r reboot · alt p shutdown (twice for the last two),
//          or type it: "shut", "reb", "lock", "sleep" … list the power actions first, ⏎ runs them
//
// Pinned apps come from config/apps.conf (the same list as the Plasma taskbar; apps.conf in
// this folder is a symlink to it). Typing searches every installed .desktop entry.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Scope {
    id: root

    property string query: ""
    property int sel: 0                     // index into results (all of them, not only the shown rows)
    property int offset: 0                  // first result shown
    property string zone: "apps"            // where the keys go: apps · power
    property int psel: 0                    // selected power button
    property var pinned: []                 // [{label, hue, entry}]
    property string armed: ""               // power button waiting for a second click
    property string kernel: ""
    property string host: ""
    property string uptime: ""

    readonly property int maxRows: 9

    IpcHandler {
        target: "launcher"
        function toggle(): void { Ui.toggleLauncher() }
        function open(): void { Ui.launcherOpen = true }
        function close(): void { Ui.launcherOpen = false }
    }

    Connections {
        target: Ui
        function onLauncherOpenChanged() {
            if (Ui.launcherOpen) {
                root.query = ""; root.sel = 0; root.offset = 0; root.armed = ""; root.zone = "apps";
                info.running = true;
                root.tabs = []; tabList.running = true;
            }
        }
    }

    // ── categories → hue + icon (one hue per category, everywhere) ──
    readonly property var pastelToNeon: ({ pink: "rose", coral: "orange", peach: "red", butter: "gold",
                                           mint: "aqua", teal: "cyan", sky: "blue", lavender: "amber", lilac: "cream" })
    function hueOf(entry) {
        const c = (entry?.categories ?? []).join(";");
        if (/TerminalEmulator|System|Settings|Monitor|HardwareSettings|PackageManager/.test(c)) return "amber";
        if (/Development|IDE|TextEditor|Building|Debugger/.test(c)) return "aqua";
        if (/WebBrowser|Network|FileTransfer|RemoteAccess/.test(c) && !/Chat|InstantMessaging|Email/.test(c)) return "blue";
        if (/Chat|InstantMessaging|Email|IRCClient|Telephony/.test(c)) return "cyan";
        if (/Audio|Video|AudioVideo|Player|Music|Graphics|Photography|Game/.test(c)) return "rose";
        if (/Security|Encryption/.test(c)) return "orange";
        if (/Clock|Calendar|Scheduling|Archiving|Compression/.test(c)) return "red";
        if (/FileManager|FileTools|Office|Viewer|Documentation|WordProcessor|Spreadsheet/.test(c)) return "gold";
        return "amber";
    }
    function iconOf(entry, hue) {
        const c = (entry?.categories ?? []).join(";");
        if (/TerminalEmulator/.test(c)) return "terminal";
        if (/Game/.test(c)) return "game";
        if (/Clock|Calendar/.test(c)) return "clock";
        return ({ amber: "settings", aqua: "code", blue: "globe", cyan: "chat", rose: "music",
                  orange: "shield", red: "clock", gold: "folder", cream: "user" })[hue] ?? "app";
    }
    function binOf(entry) {
        const cmd = (entry?.command ?? []).filter(a => !a.startsWith("%") && !a.startsWith("-") && a !== "env" && !a.includes("="));
        if (!cmd.length) return "";
        if (cmd[0].endsWith("flatpak")) return (cmd.find(a => /^[a-z]+\.[\w.]+$/i.test(a)) ?? "flatpak").split(".").pop().toLowerCase();
        return cmd[0].split("/").pop();
    }

    // ── pinned apps: config/apps.conf ──
    FileView {
        id: appsConf
        path: Quickshell.shellDir + "/apps.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.loadPinned()
    }
    function loadPinned() {
        const out = [];
        for (const raw of appsConf.text().split("\n")) {
            const l = raw.trim();
            if (!l || l.startsWith("#")) continue;
            if (l.startsWith("[")) break;                     // [fill] section: not shown
            const f = l.split("|").map(s => s.trim());
            if (f.length < 3) continue;
            const entry = f[2].split(/\s+/).map(id => DesktopEntries.byId(id)).find(e => e) ?? null;
            if (entry) out.push({ label: f[0], hue: root.pastelToNeon[f[1]] ?? root.hueOf(entry), entry });
        }
        root.pinned = out;
    }
    Connections { target: DesktopEntries.applications; function onValuesChanged() { root.loadPinned() } }

    // ── search: word-prefix beats substring beats keyword ──
    function score(e, q) {
        const name = (e.name ?? "").toLowerCase();
        if (name === q) return 100;
        if (name.startsWith(q)) return 80;
        if (name.split(/[\s\-_.]/).some(w => w.startsWith(q))) return 60;
        if (name.includes(q)) return 40;
        const extra = [(e.genericName ?? ""), (e.keywords ?? []).join(" "), root.binOf(e), e.id ?? ""].join(" ").toLowerCase();
        if (extra.includes(q)) return 20;
        return 0;
    }
    // ── browser tabs (bin/nook-tabs + the nook tabs extension): "@" alone lists them all,
    //    "@word" only tabs, any other query shows matching tabs below the apps ──
    property var tabs: []
    readonly property bool tabMode: /^\s*@/.test(root.query)
    Process {
        id: tabList
        command: ["nook-tabs", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const l of this.text.split("\n")) {
                    try { if (l.trim()) out.push(JSON.parse(l)); } catch (e) {}
                }
                root.tabs = out;
            }
        }
    }
    function hostOf(url) { const m = /^\w+:\/\/([^/]+)/.exec(url ?? ""); return m ? m[1].replace(/^www\./, "") : "" }
    function tabHits(q) {
        return root.tabs.filter(t => q === "" || (t.title + " " + root.hostOf(t.url)).toLowerCase().includes(q))
                        .map(t => ({ label: t.title || root.hostOf(t.url), hue: t.audible ? "gold" : "cyan", tab: t }));
    }
    function closeTab(i) {
        const r = root.results[i];
        if (!r?.tab) return;
        Quickshell.execDetached(["nook-tabs", "close", String(r.tab.id)]);
        root.tabs = root.tabs.filter(t => t.id !== r.tab.id);
    }

    readonly property var results: {
        const q = root.query.trim().toLowerCase();
        if (root.tabMode) return root.tabHits(q.slice(1).trim());
        if (q === "") return root.pinned;
        const hits = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            const s = root.score(e, q);
            if (s > 0) hits.push({ s, e });
        }
        hits.sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name));
        const seen = new Set();
        return root.powerHits(q).concat(hits.filter(h => !seen.has(h.e.name) && seen.add(h.e.name))
                   .map(h => ({ label: h.e.name.toLowerCase(), hue: root.hueOf(h.e), entry: h.e })))
                   .concat(q.length >= 2 ? root.tabHits(q) : []);
    }
    onResultsChanged: { sel = 0; offset = 0 }
    onQueryChanged: armed = ""
    // keep the selection on screen
    onSelChanged: {
        if (sel < offset) offset = sel;
        else if (sel >= offset + maxRows) offset = sel - maxRows + 1;
    }
    function move(step, wrap) {
        const n = root.results.length;
        if (!n) return;
        root.sel = wrap ? (root.sel + step + n) % n : Math.max(0, Math.min(n - 1, root.sel + step));
    }

    function launch(i) {
        const r = root.results[i];
        if (!r) return;
        if (r.power) { root.pressPower(r.power); return; }
        if (r.tab) {
            Quickshell.execDetached(["nook-tabs", "activate", String(r.tab.id)]);
            Ui.launcherOpen = false;
            return;
        }
        r.entry.execute();
        Ui.launcherOpen = false;
    }

    // ── power: click once to arm, again to run (lock and sleep run at once) ──
    readonly property var power: [
        { id: "lock",     hue: "orange", key: Qt.Key_L, cap: "L", cmd: ["loginctl", "lock-session"], confirm: false,
          words: ["lock"] },
        { id: "sleep",    hue: "blue",   key: Qt.Key_S, cap: "S", cmd: ["systemctl", "suspend"],     confirm: false,
          words: ["sleep", "suspend"] },
        { id: "reboot",   hue: "gold",   key: Qt.Key_R, cap: "R", cmd: ["systemctl", "reboot"],      confirm: true,
          words: ["reboot", "restart"] },
        { id: "shutdown", hue: "rose",   key: Qt.Key_P, cap: "P", cmd: ["systemctl", "poweroff"],    confirm: true,
          words: ["shutdown", "poweroff", "halt", "off"] }
    ]
    // typed power words: two letters are enough ("sh", "reb")
    function powerHits(q) {
        if (q.length < 2) return [];
        return root.power.filter(p => p.words.some(w => w.startsWith(q)))
                         .map(p => ({ label: p.id, hue: p.hue, power: p }));
    }
    function pickPower(i) {
        root.psel = (i + root.power.length) % root.power.length;
        root.armed = "";
    }
    function pressPower(p) {
        if (p.confirm && root.armed !== p.id) { root.armed = p.id; return; }
        Ui.launcherOpen = false;
        Quickshell.execDetached(p.cmd);
    }

    // header facts, read each time the menu opens
    Process {
        id: info
        command: ["sh", "-c", "uname -r; hostname -s; awk '{s=int($1); printf \"%02d:%02d:%02d\\n\", s/3600, s%3600/60, s%60}' /proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = this.text.trim().split("\n");
                root.kernel = l[0] ?? ""; root.host = l[1] ?? ""; root.uptime = l[2] ?? "";
            }
        }
    }

    // NOOK banner, coloured in 5-column bands that shift two columns per row (fire → ice, diagonal)
    readonly property var banner: [
        "███╗   ██╗ ██████╗  ██████╗ ██╗  ██╗",
        "████╗  ██║██╔═══██╗██╔═══██╗██║ ██╔╝",
        "██╔██╗ ██║██║   ██║██║   ██║█████╔╝ ",
        "██║╚██╗██║██║   ██║██║   ██║██╔═██╗ ",
        "██║ ╚████║╚██████╔╝╚██████╔╝██║  ██╗",
        "╚═╝  ╚═══╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝"
    ]
    function bannerRow(row) {
        const chars = Array.from(root.banner[row]);
        let html = "", cur = -1;
        for (let col = 0; col < chars.length; col++) {
            const k = Math.floor((col + 2 * row) / 5) % 9;
            if (k !== cur) { if (cur >= 0) html += "</span>"; html += `<span style="color:${Theme.rainbow[k]}">`; cur = k; }
            html += chars[col] === " " ? "&nbsp;" : chars[col];
        }
        return html + "</span>";
    }

    // hexdump of the query (or of "nook" while empty), 8 bytes a line, 3 lines
    function hexdump(s) {
        const bytes = Array.from(unescape(encodeURIComponent(s || "nook <3 λ"))).map(c => c.charCodeAt(0));
        while (bytes.length < 24) bytes.push([0xca, 0xfe, 0x13, 0x37, 0xbe, 0xef, 0x42, 0x00][bytes.length % 8]);
        const lines = [];
        for (let i = 0; i < 24; i += 8)
            lines.push(i.toString(16).padStart(4, "0") + "  " + bytes.slice(i, i + 8).map(b => b.toString(16).padStart(2, "0")).join(" "));
        return lines.join("\n");
    }

    component Mono: Text {
        color: Theme.ink
        font.family: Theme.font
        font.pixelSize: 12
    }
    component Label: Mono {
        color: Theme.faint
        font.pixelSize: Theme.label
        font.bold: true
        font.letterSpacing: 1.2
    }

    HyprlandFocusGrab {
        windows: [panel]
        active: Ui.launcherOpen && panel.visible
        onCleared: Ui.launcherOpen = false
    }

    PanelWindow {
        id: panel
        visible: Ui.launcherOpen
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "nook-launcher"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        exclusionMode: ExclusionMode.Ignore
        anchors { bottom: true; left: true }
        margins { bottom: Theme.bar + Theme.edge; left: Theme.edge }
        implicitWidth: 560
        implicitHeight: card.implicitHeight + 40
        color: "transparent"
        onVisibleChanged: if (visible) focusTimer.restart()
        // the layer surface takes keyboard focus a moment after it maps
        Timer { id: focusTimer; interval: 50; onTriggered: input.forceActiveFocus() }

        // the cyan neon halo around the card
        RectangularShadow {
            anchors.fill: card
            radius: Theme.radius
            blur: 24
            spread: 0
            color: Theme.alpha(Theme.cyan, 0.45)
        }

        Rectangle {
            id: card
            x: 10; y: 10
            width: 540
            implicitHeight: body.implicitHeight
            radius: Theme.radius
            color: Theme.bg100
            border.width: 1
            border.color: Theme.cyan
            clip: true

            ColumnLayout {
                id: body
                width: parent.width
                spacing: 0

                // ── header: banner + who ──
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Layout.bottomMargin: 10
                    spacing: 10
                    Column {
                        Repeater {
                            model: root.banner.length
                            Text {
                                required property int index
                                textFormat: Text.RichText
                                text: root.bannerRow(index)
                                font.family: Theme.font
                                font.pixelSize: 10
                                lineHeightMode: Text.FixedHeight
                                lineHeight: 11
                            }
                        }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true; shadowColor: Theme.red
                            shadowBlur: 0.35; shadowOpacity: 0.3
                            shadowHorizontalOffset: 0; shadowVerticalOffset: 0
                        }
                    }
                    RowLayout {
                        spacing: 12
                        Text {
                            text: (Quickshell.env("USER") ?? "root") + "@" + (root.host || "nook")
                            color: Theme.ink; font.family: Theme.pixel; font.pixelSize: 22
                        }
                        Mono { text: "kernel " + root.kernel.split("-")[0]; color: Theme.muted; font.pixelSize: Theme.small }
                        Mono { text: "up " + root.uptime; color: Theme.muted; font.pixelSize: Theme.small }
                        Mono { text: "● hyprland"; color: Theme.aqua; font.pixelSize: Theme.small }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; opacity: 0.8 }

                // ── prompt ──
                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Layout.topMargin: 12
                    Layout.bottomMargin: 12
                    implicitHeight: 34
                    radius: Theme.radiusSm
                    color: Theme.bg000
                    border.width: 1
                    border.color: Theme.cyan
                    RowLayout {
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        spacing: 8
                        Mono { text: "λ ~/"; color: Theme.aqua; font.bold: true; font.pixelSize: Theme.body }
                        Mono { text: ">"; color: Theme.faint; font.pixelSize: Theme.body }
                        TextInput {
                            id: input
                            Layout.fillWidth: true
                            text: root.query
                            onTextChanged: root.query = text
                            focus: true
                            color: Theme.ink
                            selectionColor: Theme.cyan
                            selectedTextColor: Theme.onAccent
                            font.family: Theme.font
                            font.pixelSize: Theme.body
                            cursorDelegate: Rectangle {
                                width: 8; height: 16
                                color: Theme.aqua
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite; running: Ui.launcherOpen
                                    PropertyAction { value: 1 } PauseAnimation { duration: 525 }
                                    PropertyAction { value: 0 } PauseAnimation { duration: 525 }
                                }
                            }
                            Connections {
                                target: Ui
                                function onLauncherOpenChanged() { if (Ui.launcherOpen) { input.text = ""; input.forceActiveFocus(); } }
                            }
                            Keys.onPressed: e => {
                                const k = e.key, ctrl = e.modifiers & Qt.ControlModifier;
                                const altPower = (e.modifiers & Qt.AltModifier) ? root.power.find(p => p.key === k) : null;
                                if (altPower) {
                                    root.zone = "power";
                                    root.psel = root.power.indexOf(altPower);
                                    root.pressPower(altPower);
                                } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
                                    root.zone = root.zone === "apps" ? "power" : "apps";
                                    root.armed = "";
                                } else if (root.zone === "power") {
                                    if (k === Qt.Key_Escape) { root.zone = "apps"; root.armed = ""; }
                                    else if (k === Qt.Key_Left || k === Qt.Key_Up) root.pickPower(root.psel - 1);
                                    else if (k === Qt.Key_Right || k === Qt.Key_Down) root.pickPower(root.psel + 1);
                                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.pressPower(root.power[root.psel]);
                                    // anything else is typing: back to the apps, the prompt takes the key
                                    else { if (e.text !== "") { root.zone = "apps"; root.armed = ""; } return; }
                                } else {
                                    if (k === Qt.Key_Escape) Ui.launcherOpen = false;
                                    else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) root.move(1, true);
                                    else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_P)) root.move(-1, true);
                                    else if (k === Qt.Key_PageDown) root.move(root.maxRows, false);
                                    else if (k === Qt.Key_PageUp) root.move(-root.maxRows, false);
                                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.launch(root.sel);
                                    else if (ctrl && k === Qt.Key_W) root.closeTab(root.sel);
                                    else if ((e.modifiers & Qt.AltModifier) && k >= Qt.Key_1 && k <= Qt.Key_9) root.launch(root.offset + k - Qt.Key_1);
                                    else return;
                                }
                                e.accepted = true;
                            }
                        }
                    }
                }

                // ── two columns: apps | sys ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 12
                    spacing: 14

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 300
                        Layout.alignment: Qt.AlignTop
                        spacing: 1
                        Label {
                            text: (root.tabMode ? "TABS // " + root.results.length + "  ⏎ show · ctrl w close"
                                   : root.query === "" ? "APPS // PINNED" : "APPS // MATCH · " + root.results.length)
                                  + (root.results.length > root.maxRows ? "  [" + (root.offset + 1) + "–" + Math.min(root.results.length, root.offset + root.maxRows) + "]" : "")
                            Layout.bottomMargin: 5
                        }
                        Repeater {
                            model: root.results.slice(root.offset, root.offset + root.maxRows)
                            Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property int at: root.offset + index
                                readonly property bool selected: at === root.sel && root.zone === "apps"
                                readonly property color hue: Theme[modelData.hue] ?? Theme.amber
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: Theme.radiusSm
                                color: selected ? Theme.soft(Theme.cyan) : rowArea.containsMouse ? Theme.bg300 : "transparent"
                                border.width: selected ? 1 : 0
                                border.color: Theme.cyan
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    spacing: 8
                                    Mono {
                                        text: "[" + String(row.at + 1).padStart(2, "0") + "]"
                                        color: row.selected ? Theme.cyan : Theme.faint
                                    }
                                    Image {
                                        source: Icons.url(row.modelData.power ? "power" : row.modelData.tab ? "globe" : root.iconOf(row.modelData.entry, row.modelData.hue), row.hue.toString())
                                        sourceSize: Qt.size(16, 16)
                                        Layout.preferredWidth: 16; Layout.preferredHeight: 16
                                        layer.enabled: true
                                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: row.hue; shadowBlur: 0.4; shadowOpacity: 0.6; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                                    }
                                    Mono { text: row.modelData.label + (row.modelData.power && root.armed === row.modelData.power.id ? "?" : ""); color: row.hue; Layout.maximumWidth: 150; elide: Text.ElideRight; font.bold: !!row.modelData.power && root.armed === row.modelData.power.id }
                                    Mono { text: ".".repeat(60); color: Theme.faint; Layout.fillWidth: true; clip: true; elide: Text.ElideNone }
                                    Mono {
                                        text: row.modelData.tab ? root.hostOf(row.modelData.tab.url)
                                            : !row.modelData.power ? root.binOf(row.modelData.entry)
                                            : root.armed === row.modelData.power.id ? "⏎ again" : "alt " + row.modelData.power.cap.toLowerCase()
                                        color: row.modelData.power && root.armed === row.modelData.power.id ? Theme.orange : Theme.muted
                                        Layout.maximumWidth: 90; elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: rowArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: { root.sel = row.at; root.zone = "apps" }
                                    onClicked: root.launch(row.at)
                                }
                            }
                        }
                        Mono {
                            visible: root.results.length === 0
                            text: root.query === "" ? "no pinned apps · edit config/apps.conf" : "λ: command not found: " + root.query
                            color: root.query === "" ? Theme.faint : Theme.orange
                            font.pixelSize: Theme.small
                            Layout.leftMargin: 6
                        }
                        Mono {
                            readonly property int below: root.results.length - root.offset - root.maxRows
                            visible: root.results.length > root.maxRows
                            text: (below > 0 ? "↓ " + below + " more" : "end of list") + (root.offset > 0 ? " · ↑ " + root.offset + " above" : "")
                            color: Theme.faint; font.pixelSize: Theme.small
                            Layout.leftMargin: 6
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: 196
                        Layout.maximumWidth: 196
                        Layout.alignment: Qt.AlignTop
                        spacing: 2
                        Label { text: "SYS // LIVE"; Layout.bottomMargin: 5 }
                        Repeater {
                            model: [
                                { k: "cpu", v: Stats.cpu, hue: Theme.amber, unit: "%" },
                                { k: "ram", v: Stats.ram, hue: Theme.aqua, unit: "%" },
                                { k: "gpu", v: Stats.gpu, hue: Theme.blue, unit: "%" },
                                { k: "tmp", v: Math.min(100, Stats.temp), hue: Theme.red, unit: "°" }
                            ]
                            Text {
                                required property var modelData
                                textFormat: Text.RichText
                                font.family: Theme.font; font.pixelSize: Theme.small
                                text: `<span style="color:${Theme.muted}">${modelData.k} </span>`
                                    + `<span style="color:${Theme.faint}">[</span>`
                                    + `<span style="color:${modelData.hue}">${"█".repeat(Math.round(modelData.v / 10))}</span>`
                                    + `<span style="color:${Theme.faint}">${"░".repeat(10 - Math.round(modelData.v / 10))}]</span>`
                                    + `<span style="color:${Theme.ink}"> ${modelData.v}${modelData.unit}</span>`
                            }
                        }
                        Text {
                            textFormat: Text.RichText
                            font.family: Theme.font; font.pixelSize: Theme.small
                            text: `<span style="color:${Theme.muted}">net </span><span style="color:${Theme.cyan}">↓ ${Stats.rate(Stats.rx)} ↑ ${Stats.rate(Stats.tx)}</span>`
                        }
                        Text {
                            textFormat: Text.RichText
                            font.family: Theme.font; font.pixelSize: Theme.small
                            text: `<span style="color:${Theme.muted}">ws  </span><span style="color:${Theme.gold}">${Hyprland.workspaces.values.length} open · on ${Hyprland.focusedMonitor?.activeWorkspace?.id ?? "?"}</span>`
                        }
                        Mono {
                            Layout.topMargin: 8
                            text: root.hexdump(root.query)
                            color: Theme.faint
                            font.pixelSize: Theme.label
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 14
                        }
                        Mono {
                            Layout.topMargin: 8
                            text: " /\\_/\\  \n( o.o ) \n > ^ <  \n/  λ  \\ "
                            color: Theme.faint
                            font.pixelSize: Theme.label
                            lineHeightMode: Text.FixedHeight
                            lineHeight: 11
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; opacity: 0.8 }

                // ── footer: bracketed power buttons ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Layout.topMargin: 10
                    Layout.bottomMargin: 12
                    spacing: 6
                    Repeater {
                        model: root.power
                        Rectangle {
                            id: pw
                            required property var modelData
                            required property int index
                            readonly property color hue: Theme[modelData.hue]
                            readonly property bool armedHere: root.armed === modelData.id
                            readonly property bool picked: root.zone === "power" && root.psel === index
                            implicitWidth: pwText.implicitWidth + pwKey.implicitWidth + 20
                            implicitHeight: 22
                            radius: Theme.radiusSm
                            color: armedHere ? hue : pwArea.containsMouse || picked ? Theme.soft(hue) : "transparent"
                            border.width: picked ? 2 : 1
                            border.color: picked ? Theme.cyan : hue
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                Mono {
                                    id: pwText
                                    text: pw.armedHere ? pw.modelData.id + "?" : pw.modelData.id
                                    color: pw.armedHere ? Theme.onAccent : pw.hue
                                    font.pixelSize: Theme.small
                                    font.bold: pw.armedHere
                                }
                                // the alt key, as a faint cap
                                Mono {
                                    id: pwKey
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "alt " + pw.modelData.cap.toLowerCase()
                                    color: pw.armedHere ? Theme.onAccent : Theme.faint
                                    font.pixelSize: Theme.label
                                }
                            }
                            MouseArea { id: pwArea; anchors.fill: parent; hoverEnabled: true; onClicked: root.pressPower(pw.modelData) }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Mono {
                        text: root.zone === "power"
                            ? (root.armed !== "" ? "⏎ again: " + root.armed : "←→ ⏎ · tab apps")
                            : root.armed !== "" ? "⏎ again: " + root.armed
                            : "↑↓ ⏎ · tab power"
                        color: root.armed !== "" ? Theme.orange : Theme.faint
                        font.pixelSize: Theme.label
                    }
                }
            }
        }
    }
}
