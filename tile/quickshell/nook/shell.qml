//@ pragma UseQApplication
// nook-tile shell — run with: qs -c nook   (Hyprland starts it, SUPER ⇧ R reloads)
// Quickshell also reloads by itself whenever a file in this folder changes.
import Quickshell
import QtQuick

ShellRoot {
    Wallpaper {}
    Widgets {}
    CheatSheet {}
    Bar {}
    Launcher {}
    ControlCenter {}
    Screens {}
}
