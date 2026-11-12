// Slower data for the desktop widgets: weather, servers, calendar (from bin/nook-feed, which
// reads ~/.config/nook/widgets.conf) and the top processes (ps). Shared by every screen.
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root
    readonly property string feed: Quickshell.env("HOME") + "/.local/bin/nook-feed"

    property var weather: ({ ok: false })
    property var srv: ({ ok: false, hosts: [] })
    property var srvHist: ({})        // name → last 24 latencies in ms (-1 = down)
    property var cal: ({ ok: false })
    property var procs: []            // [{ pid, name, cpu, mem }]

    function parse(text, fallback) {
        try { return JSON.parse(text) } catch (e) { return fallback }
    }

    // ── weather, every 15 min (nook-feed caches 10 min) ──
    Process {
        id: wx
        command: [root.feed, "weather"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.weather = root.parse(this.text, { ok: false, error: "no data" });
                if (root.weather.ok !== true) wxRetry.restart();
            }
        }
    }
    Timer { interval: 15 * 60000; running: Settings.shown("widget.weather"); repeat: true; triggeredOnStart: true; onTriggered: wx.running = true }
    // the shell starts before the wifi is up: a failed fetch tries again in 30 s, not 15 min
    Timer { id: wxRetry; interval: 30000; onTriggered: if (Settings.shown("widget.weather")) wx.running = true }

    // ── servers, every 10 s ──
    Process {
        id: ping
        command: [root.feed, "srv"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(this.text, { ok: false, hosts: [] });
                const h = Object.assign({}, root.srvHist);
                for (const x of r.hosts ?? [])
                    h[x.name] = (h[x.name] ?? []).concat([x.up ? x.ms : -1]).slice(-24);
                root.srvHist = h;
                root.srv = r;
            }
        }
    }
    Timer { interval: 10000; running: Settings.shown("widget.srv"); repeat: true; triggeredOnStart: true; onTriggered: ping.running = true }

    // ── calendar, every 5 min ──
    Process {
        id: caldav
        command: [root.feed, "cal"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.cal = root.parse(this.text, { ok: false, error: "no data" });
                if (root.cal.ok !== true && (root.cal.error ?? "").indexOf("URLError") >= 0) calRetry.restart();
            }
        }
    }
    Timer { interval: 5 * 60000; running: Settings.shown("widget.cal"); repeat: true; triggeredOnStart: true; onTriggered: caldav.running = true }
    Timer { id: calRetry; interval: 30000; onTriggered: if (Settings.shown("widget.cal")) caldav.running = true }
    function refreshCal() { caldav.running = true }

    // ── widgets.conf itself, for the control center's nook tab: read with `nook-feed conf`,
    //    changed one key at a time with `nook-feed set|unset`, then the feeds poll again ──
    property var conf: ({ ok: false, srv: [], weather: {} })
    property string confError: ""
    property var pending: []
    Process {
        id: confRead
        running: true
        command: [root.feed, "conf"]
        stdout: StdioCollector { onStreamFinished: root.conf = root.parse(this.text, { ok: false, srv: [], weather: {} }) }
    }
    Process {
        id: confWrite
        stderr: StdioCollector { onStreamFinished: { if (this.text.trim()) root.confError = this.text.trim() } }
        onExited: code => {
            if (code === 0) root.confError = "";
            if (root.pending.length) return root.next();
            confRead.running = true;
            ping.running = true;
            wx.running = true;
            caldav.running = true;
        }
    }
    function next() {
        confWrite.command = [root.feed].concat(root.pending[0]);
        root.pending = root.pending.slice(1);
        confWrite.running = true;
    }
    function write(args) {
        root.pending = root.pending.concat([args]);
        if (!confWrite.running) root.next();
    }
    function setConf(section, key, value) { root.write(["set", section, key, value]) }
    function unsetConf(section, key) {
        if (section === "srv") {
            const h = Object.assign({}, root.srvHist);
            delete h[key];
            root.srvHist = h;
        }
        root.write(["unset", section, key]);
    }

    // ── top processes by cpu (idle ones by ram), every 3 s. top's 2nd sample is the current load (ps only has
    //    lifetime averages); C locale so the numbers use a dot ──
    Process {
        id: top
        environment: ({ LC_ALL: "C" })
        command: ["sh", "-c", "top -b -n2 -d0.5 -w 200 | awk '/^ *PID/{n++;next} n==2 && NF>=12 && $1>2 && $12!=\"top\" {print $1,$9,$10,$12}' | sort -k2,2nr -k3,3nr | head -5"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.procs = this.text.trim().split("\n").filter(l => l.trim()).map(l => {
                    const f = l.trim().split(/\s+/);
                    return { pid: f[0], cpu: Number(f[1]), mem: Number(f[2]), name: f.slice(3).join(" ") };
                });
            }
        }
    }
    Timer { interval: 3000; running: Settings.shown("widget.proc"); repeat: true; triggeredOnStart: true; onTriggered: top.running = true }
}
