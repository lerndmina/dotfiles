#!/bin/sh -e

killall -SIGUSR1 gpu-screen-recorder
notify-send -t 5000 -u normal -- "GPU Screen Recorder" "Replay saved"
