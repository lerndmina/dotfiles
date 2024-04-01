#!/bin/sh

killall -SIGINT gpu-screen-recorder
killall yad

# Create a YAD notification
(
  while true; do
    echo "icon:media-record"
    echo "tooltip:Recording started"
    echo "menu:Currently recording..."
    sleep 1
  done
) | yad --notification --listen &

# Get the name of the primary display
display=$(xrandr --query | grep ' primary' | awk '{print $1}')

video_path="$HOME/Videos/replays"
mkdir -p "$video_path"
gpu-screen-recorder -w "$display" -f 60 -a "$(pactl get-default-sink).monitor" -c mkv -r 300 -o "$video_path"
# -f 60: 60 fps
# -a "$(pactl get-default-sink).monitor": record audio from default sink
# -c mkv: output format is mkv
# -r 300: record for 300 seconds
# -o "$video_path": save the video to $HOME/Videos
