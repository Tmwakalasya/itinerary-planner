#!/bin/zsh
# Frames a raw simulator recording for sharing: trims the home screen off both
# ends, then writes
#   City Tourist demo.mp4             1080x1920, the screen in a slim phone
#                                     bezel on a warm background, faded in/out
#   City Tourist demo (full res).mp4  the trimmed screen alone, at full size
#
#   Scripts/finish-demo.sh raw.mov [output-dir]
#
# TRIM_START / TRIM_END (seconds) override how much comes off each end.
set -euo pipefail
raw=$1
out=${2:-"$HOME/Desktop/City Tourist demo"}
start=${TRIM_START:-3.0}
end_trim=${TRIM_END:-3.0}
mkdir -p "$out"
work=$(mktemp -d)

total=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$raw")
length=$(echo "$total - $start - $end_trim" | bc)
fade_out=$(echo "$length - 0.7" | bc)

# Rounded-corner masks, drawn at twice the size and scaled down for smooth edges.
mask() {  # width height radius file
  local W=$(($1 * 2)) H=$(($2 * 2)) R=$(($3 * 2))
  ffmpeg -v error -y -f lavfi -i "color=black:s=${W}x${H},format=gray" -frames:v 1 -vf \
    "geq=lum='255*gt(between(X,${R},$((W-R)))+between(Y,${R},$((H-R)))+lte(hypot(X-${R},Y-${R}),${R})+lte(hypot(X-$((W-R)),Y-${R}),${R})+lte(hypot(X-${R},Y-$((H-R))),${R})+lte(hypot(X-$((W-R)),Y-$((H-R))),${R}),0)',scale=${1}:${2}:flags=lanczos" "${4}"
}
mask 782 1700 105 "$work/screen.png"
mask 814 1732 121 "$work/bezel.png"

d=$(echo "$length + 1" | bc)
cat > "$work/frame.filter" <<FILTER
gradients=s=1080x1920:c0=0xF8F4EF:c1=0xECE5DB:x0=540:y0=0:x1=540:y1=1920:r=60:d=${d}[bg];
[0:v]setpts=PTS-STARTPTS,fps=60,scale=782:1700:flags=lanczos,format=rgba[scr];
[1:v]setpts=PTS-STARTPTS,format=gray[smask];
[scr][smask]alphamerge[screen];
[2:v]setpts=PTS-STARTPTS,format=gray,split[bm1][bm2];
color=c=black:s=814x1732:r=60:d=${d}[sh0];
[sh0][bm1]alphamerge,colorchannelmixer=aa=0.28,pad=1014:1932:100:100:color=black@0,gblur=sigma=30[shadow];
color=c=0x0E0E10:s=814x1732:r=60:d=${d}[bz0];
[bz0][bm2]alphamerge[bezel];
[bg][shadow]overlay=x=33:y=18[b1];
[b1][bezel]overlay=x=133:y=94[b2];
[b2][screen]overlay=x=149:y=110,fade=t=in:st=0:d=0.6:color=0xF3EEE7,fade=t=out:st=${fade_out}:d=0.7:color=0xF3EEE7,format=yuv420p[out]
FILTER

echo "Framing…"
ffmpeg -v error -y -ss "$start" -t "$length" -i "$raw" -loop 1 -i "$work/screen.png" -loop 1 -i "$work/bezel.png" \
  -filter_complex_script "$work/frame.filter" -map "[out]" -t "$length" \
  -c:v libx264 -preset slow -crf 18 -r 60 -movflags +faststart "$out/City Tourist demo.mp4"

echo "Full resolution…"
ffmpeg -v error -y -ss "$start" -t "$length" -i "$raw" -vf "setpts=PTS-STARTPTS,fps=60,format=yuv420p" \
  -t "$length" -c:v libx264 -preset slow -crf 16 -movflags +faststart "$out/City Tourist demo (full res).mp4"

echo "Done: $out"
