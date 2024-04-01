#!/bin/sh

# Notify that recording is stopped
notify-send -t 5000 -u normal -- "GPU Screen Recorder" "Replay stopped"

killall -SIGUSR1 gpu-screen-recorder
killall yad
sleep 2
killall -SIGINT gpu-screen-recorder
