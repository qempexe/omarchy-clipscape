import QtQuick
import Quickshell
import Quickshell.Io
import "../js/Clips.js" as Clips
import "../js/Schema.js" as Schema

// The history: what is kept, the watcher that keeps it, and the helper jobs that put a
// clip back on the clipboard. The only writer of history.json; the helper only reads it.
Item {
    id: root

    visible: false

    property var cfg: null
    property bool paused: false
    readonly property var cfgSafe: cfg ? cfg : Schema.defaults

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/omarchy-clipscape"
    readonly property string imgDir: stateDir + "/images"
    readonly property string historyPath: stateDir + "/history.json"
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("../../bin/clipscape").toString().replace(/^file:\/\//, ""))

    property var clips: []
    property bool ready: false       // history.json has been read (or there was none)
    property bool dirReady: false
    property int revision: 0         // bumped on every change, for views that cache
    property var lastCaptured: null

    readonly property int pinnedCount: clips.filter(c => c.pinned).length
    readonly property var latest: clips.length > 0 ? clips[0] : null

    signal changed()
    signal captured(var clip)

    function now() { return Date.now() }

    // ---- reading and writing -----------------------------------------------------
    function readText(fv) {
        try { return String(typeof fv.text === "function" ? fv.text() : fv.text) } catch (e) { return "" }
    }

    function setClips(list, keepRevision) {
        clips = list
        if (!keepRevision) revision++
        changed()
    }

    property bool saving: false
    function save() {
        if (!ready || !dirReady) return
        saving = true
        historyFile.setText(Clips.serialize(clips.map(c => {
            const o = {}
            for (const k in c) if (k.charAt(0) !== "_") o[k] = c[k]
            return o
        })))
        saveFallback.restart()
    }
    // after a save, the jobs waiting for it can read the file
    function onSaved() {
        saving = false
        saveFallback.stop()
        runJobs()
    }
    Timer { id: saveFallback; interval: 1500; onTriggered: root.onSaved() }

    FileView {
        id: historyFile
        path: root.dirReady ? root.historyPath : ""
        atomicWrites: true
        printErrors: false
        onLoaded: root.absorbFile(root.readText(historyFile))
        onLoadFailed: root.firstRun()
        onSaved: root.onSaved()
        onSaveFailed: root.onSaved()
    }

    function absorbFile(text) {
        if (ready) return
        setClips(Clips.parseStore(text, imgDir, now()))
        ready = true
        prune()
        gcSoon()
    }

    // no history yet: bring in Omarchy's own, once
    function firstRun() {
        if (ready) return
        importProc.command = ["python3", helper, "import", "--max-image", String(cfgSafe.maxImageMB * 1048576)]
        importProc.running = true
    }
    Process {
        id: importProc
        stdout: StdioCollector {
            onStreamFinished: {
                let list = []
                try { list = JSON.parse(String(text || "[]")) } catch (e) { list = [] }
                const t = root.now()
                const out = []
                for (const v of Array.isArray(list) ? list : []) {
                    const c = Clips.normalize(v, root.imgDir, t)
                    if (!c) continue
                    if (c.kind === "text") c.secret = Clips.secretKind(c.text) !== ""
                    if (c.secret && root.cfgSafe.secrets === "skip") continue
                    out.push(c)
                }
                root.ready = true
                root.setClips(Clips.cap(Clips.parseStore(Clips.serialize(out), root.imgDir, t), root.cfgSafe.historyLimit))
                root.save()
            }
        }
        onExited: function(code) {
            if (!root.ready) { root.ready = true; root.setClips([]); root.save() }
        }
    }

    // the folder, private, before anything is read or written
    Component.onCompleted: { mkdir.running = true; reap.running = true }
    Process {
        id: mkdir
        command: ["sh", "-c", 'umask 077; mkdir -p "$1/images" && chmod 700 "$1" "$1/images"', "sh", root.stateDir]
        onExited: {
            root.dirReady = true
            secureProc.running = true
        }
    }
    Process { id: secureProc; command: ["python3", root.helper, "secure"] }

    // ---- what comes in ------------------------------------------------------------
    // a copy Clipscape made itself comes back through the watcher: it was already
    // counted when it was used, so it is ignored once
    property string echoKey: ""
    property real echoUntil: 0

    function absorbCapture(line) {
        if (paused || !ready) return
        let v
        try { v = JSON.parse(String(line || "")) } catch (e) { return }
        const c = Clips.normalize(v, imgDir, now())
        if (!c) return
        const app = c.app.toLowerCase()
        if (app !== "" && Schema.skipList(cfgSafe.skipApps).some(s => app.indexOf(s) >= 0)) return
        if (c.kind === "image" && !cfgSafe.images) return
        if (c.kind === "text") {
            if (c.text.length > cfgSafe.maxTextKB * 1024) return
            c.secret = Clips.secretKind(c.text) !== ""
            if (c.secret && cfgSafe.secrets === "skip") return
            if (cfgSafe.secrets === "keep") c.secret = false
        }
        const key = Clips.keyOf(c)
        if (key === echoKey && now() < echoUntil) { echoKey = ""; return }
        setClips(Clips.add(clips, c, cfgSafe.historyLimit))
        lastCaptured = clips[0]
        save()
        captured(clips[0])
        gcSoon()
    }

    // ---- the watcher ----------------------------------------------------------------
    // One wl-paste --watch for everything; the helper decides what the copy is. It only
    // runs while recording, so while paused nothing reads the clipboard at all.
    readonly property string watchKey: [cfgSafe.images ? "1" : "0", cfgSafe.maxTextKB * 1024, cfgSafe.maxImageMB * 1048576,
                                        Schema.skipList(cfgSafe.skipApps).join(",")].join("|")
    function watchCommand() {
        const k = watchKey.split("|")
        return ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--watch", "python3", helper, "capture",
                "--images", k[0], "--max-text", k[1], "--max-image", k[2], "--skip", k.slice(3).join("|")]
    }
    readonly property bool wantWatch: ready && !paused && reaped
    property bool reaped: false
    property int restarts: 0

    // watchers left behind by an earlier shell are stopped first
    function escapeRe(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&") }
    Process {
        id: reap
        command: ["pkill", "-f", "wl-paste --watch python3 " + root.escapeRe(root.helper) + " capture"]
        onExited: root.reaped = true
    }

    Process {
        id: watcher
        running: false
        stdout: SplitParser { onRead: function(line) { root.absorbCapture(line) } }
        onExited: if (root.wantWatch) restartTimer.restart()
    }
    // a watcher that dies is started again, waiting longer each time it keeps dying
    Timer {
        id: restartTimer
        interval: Math.min(30000, 1000 * Math.pow(2, Math.min(5, root.restarts)))
        onTriggered: {
            root.restarts++
            root.syncWatcher()
        }
    }
    Timer { interval: 60000; running: watcher.running; onTriggered: root.restarts = 0 }

    function syncWatcher() {
        if (wantWatch && !watcher.running) {
            watcher.command = watchCommand()
            watcher.running = true
        } else if (!wantWatch && watcher.running) {
            watcher.running = false
        }
    }
    onWantWatchChanged: syncWatcher()
    // new settings for the watcher: start it again with them
    onWatchKeyChanged: if (watcher.running) { watcher.running = false; Qt.callLater(syncWatcher) }

    // ---- changing the history ----------------------------------------------------------
    function byId(id) { return Clips.byId(clips, id) }

    function change(list) {
        setClips(list)
        save()
        gcSoon()
    }

    function remove(ids) { change(Clips.remove(clips, ids)) }
    function clearUnpinned() { change(Clips.clearUnpinned(clips)) }
    function setPinned(id, on) { change(Clips.setPinned(clips, id, on)) }
    function rename(id, label) { change(Clips.update(clips, id, { label: String(label || "").replace(/[\u0000-\u001f]/g, " ").trim().slice(0, 60) })) }
    function movePin(id, d) { change(Clips.movePin(clips, id, d)) }

    // new text (an edit, a transform, marked clips joined): a clip of its own, on top
    function addText(text) {
        const t = String(text || "")
        if (t.trim() === "" || t.length > Clips.MAX_TEXT) return ""
        const c = Clips.normalize({ kind: "text", text: t, at: now() }, imgDir, now())
        if (!c) return ""
        c.secret = cfgSafe.secrets !== "keep" && Clips.secretKind(t) !== ""
        setClips(Clips.add(clips, c, cfgSafe.historyLimit))
        save()
        return clips[0].id
    }

    // forget what Forget clips after and Forget secrets after allow
    function prune() {
        if (!ready) return
        const secretMs = cfgSafe.secrets === "mask" ? cfgSafe.secretMinutes * 60000 : 0
        const next = Clips.prune(Clips.cap(clips, cfgSafe.historyLimit), Schema.keepMs(cfgSafe), secretMs, now())
        if (next.length !== clips.length) change(next)
    }
    Timer { interval: 30000; repeat: true; running: root.ready; onTriggered: root.prune() }
    readonly property string pruneKey: cfgSafe.historyLimit + "/" + cfgSafe.keepFor + "/" + cfgSafe.secrets + "/" + cfgSafe.secretMinutes
    onPruneKeyChanged: Qt.callLater(prune)

    // pictures no clip uses any more are deleted a little later
    function gcSoon() { gcTimer.restart() }
    Timer { id: gcTimer; interval: 4000; onTriggered: if (!root.saving) gcProc.running = true; else restart() }
    Process { id: gcProc; command: ["python3", root.helper, "gc"] }

    // ---- putting a clip back --------------------------------------------------------
    property var jobs: []
    function queue(args) {
        jobs = jobs.concat([args])
        if (!saving) runJobs()
    }
    function runJobs() {
        if (jobProc.running || jobs.length === 0 || saving) return
        const q = jobs.slice()
        jobProc.command = ["python3", helper].concat(q.shift())
        jobs = q
        jobProc.running = true
    }
    Process {
        id: jobProc
        onExited: Qt.callLater(root.runJobs)
    }

    // how: "copy" only, "paste" with Paste with, or "type" (types it out)
    function use(id, how) {
        const c = byId(id)
        if (!c) return false
        echoKey = Clips.keyOf(c)
        echoUntil = now() + 4000
        const moved = cfgSafe.usedToTop ? Clips.add(clips, Object.assign({}, c, { at: now() }), cfgSafe.historyLimit)
                                        : Clips.update(clips, id, { uses: c.uses + 1, last: now() })
        setClips(moved)
        save()
        const args = ["copy", id]
        if (how === "paste") args.push("--paste", cfgSafe.pasteKeys)
        else if (how === "type") args.push("--paste", "type")
        if (c.secret && cfgSafe.clearSecretSeconds > 0) args.push("--clear-after", String(cfgSafe.clearSecretSeconds))
        queue(args)
        return true
    }

    // several clips, joined in the order given, as one new clip
    function useMany(ids, how) {
        const list = ids.map(id => byId(id)).filter(c => c && c.kind === "text")
        if (list.length === 0) return false
        if (list.length === 1) return use(list[0].id, how)
        const id = addText(Clips.joined(list, cfgSafe.joinWith))
        return id !== "" && use(id, how)
    }
}
