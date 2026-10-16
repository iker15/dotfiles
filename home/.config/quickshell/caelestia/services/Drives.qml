pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Discos externos conectados (USB, discos duros portátiles...): lsblk cada vez que udev avisa
// de un cambio en los discos y, por si acaso, cada pocos segundos (montar no siempre avisa).
Singleton {
    id: root

    property list<var> list: []
    readonly property bool present: list.length > 0
    property string ejecting: ""

    function refresh(): void {
        lsblk.running = true;
    }

    function eject(drive: var): void {
        if (ejectProc.running)
            return;
        const unmounts = drive.parts.filter(p => p.mounts.length > 0).map(p => `udisksctl unmount -b '${p.path}'`);
        root.ejecting = drive.path;
        ejectProc.command = ["sh", "-c", [...unmounts, `udisksctl power-off -b '${drive.path}'`].join(" && ")];
        ejectProc.running = true;
    }

    function open(path: string): void {
        Quickshell.execDetached(["xdg-open", path]);
    }

    function formatSize(bytes: real): string {
        const gb = bytes / 1073741824;
        if (gb >= 1000)
            return `${(gb / 1024).toFixed(1)} TB`;
        if (gb >= 1)
            return `${gb.toFixed(gb >= 100 ? 0 : 1)} GB`;
        return `${Math.round(bytes / 1048576)} MB`;
    }

    Process {
        id: lsblk

        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,HOTPLUG,TRAN,SIZE,LABEL,MODEL,MOUNTPOINTS,FSAVAIL,FSSIZE"]
        stdout: StdioCollector {
            onStreamFinished: {
                let devs = [];
                try {
                    devs = JSON.parse(text).blockdevices ?? [];
                } catch (e) {
                    return;
                }
                const isHot = d => d.hotplug === true || d.hotplug === "1" || d.hotplug === 1;
                root.list = devs.filter(d => d.type === "disk" && isHot(d) && d.size > 0).map(d => {
                    const kids = (d.children ?? []).length > 0 ? d.children : [d];
                    const parts = kids.map(p => ({
                                path: p.path,
                                label: p.label ?? "",
                                mounts: (p.mountpoints ?? []).filter(m => m),
                                avail: Number(p.fsavail ?? 0),
                                size: Number(p.fssize ?? 0)
                            }));
                    const named = parts.find(p => p.label);
                    return {
                        path: d.path,
                        name: named ? named.label : (d.model ?? "").trim() || d.name,
                        model: (d.model ?? "").trim(),
                        size: Number(d.size),
                        usb: d.tran === "usb",
                        parts: parts
                    };
                });
            }
        }
    }

    Process {
        id: ejectProc

        onExited: {
            root.ejecting = "";
            root.refresh();
        }
    }

    Process {
        running: true
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser {
            onRead: debounce.restart()
        }
    }

    Timer {
        id: debounce

        interval: 400
        onTriggered: root.refresh()
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 5000
        onTriggered: root.refresh()
    }
}
