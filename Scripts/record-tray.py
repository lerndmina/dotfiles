#!/usr/bin/env python3
"""Recording-indicator tray icon for screenshot.sh --record.

Plasma 6 only renders StatusNotifierItem (SNI) tray icons, which the old
GtkStatusIcon-based tools (yad) cannot provide on Wayland. QSystemTrayIcon
speaks SNI natively, so this gives a real red "recording" dot with a Stop
action. Clicking the dot or its menu item sends SIGINT to the recorder
(gpu-screen-recorder), which finalizes the file; the shell script then uploads.

Usage: record-tray.py <recorder_pid> [region_label]
"""
import os
import signal
import sys

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QAction, QColor, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import QApplication, QMenu, QSystemTrayIcon


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    pid = int(sys.argv[1])
    label = sys.argv[2] if len(sys.argv) > 2 else ""

    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    if not QSystemTrayIcon.isSystemTrayAvailable():
        # No tray host; let the shell script's notification handle stopping.
        return 1

    # Draw a red recording dot (no theme icon needed).
    pix = QPixmap(64, 64)
    pix.fill(Qt.transparent)
    painter = QPainter(pix)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.setBrush(QColor(220, 40, 40))
    painter.setPen(Qt.NoPen)
    painter.drawEllipse(8, 8, 48, 48)
    painter.end()

    tray = QSystemTrayIcon(QIcon(pix))
    tooltip = "● Recording — click to stop & upload"
    if label:
        tooltip = f"● Recording {label} — click to stop & upload"
    tray.setToolTip(tooltip)

    def stop() -> None:
        try:
            os.kill(pid, signal.SIGINT)
        except ProcessLookupError:
            pass
        app.quit()

    menu = QMenu()
    stop_action = QAction("⏹  Stop recording & upload")
    stop_action.triggered.connect(stop)
    menu.addAction(stop_action)
    tray.setContextMenu(menu)

    def on_activated(reason) -> None:
        if reason == QSystemTrayIcon.Trigger:  # left click
            stop()

    tray.activated.connect(on_activated)
    tray.show()

    # If the recorder exits on its own (e.g. it crashed), drop the tray icon.
    def check_recorder() -> None:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            app.quit()

    timer = QTimer()
    timer.timeout.connect(check_recorder)
    timer.start(1000)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
