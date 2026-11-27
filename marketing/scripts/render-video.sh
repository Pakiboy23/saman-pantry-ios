#!/usr/bin/env bash
# Builds the Product Hunt launch video: ten 4.0s shots on a 120 BPM grid
# (each shot rendered 4.25s, joined with 0.25s crossfades), 1920x1080, H.264.
#
# Raw screen recordings are NOT in the repo (they show personal files, family
# names and the owner's voice). Put them in marketing/launch-video/footage/:
#   old-build-capture.mp4   1206x2622 recording: home -> Capture -> Record -> spinners
#   nov17-bhindi-run.mov    the Nov 17 build-204 run: Review + "Ingredients saved"
# Cut points below only use clean ranges (no file picker, no "Mom", no family book).
#
# Optional: MUSIC=path/to/track.mp3 (ideally 120 BPM) to score it.
# Needs: node + playwright, ffmpeg, ImageMagick. Run scripts/fetch-fonts.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
V=launch-video; B=build/video
OLD=$V/footage/old-build-capture.mp4
NEW=$V/footage/nov17-bhindi-run.mov
for f in fonts/fonts-local.css "$OLD" "$NEW"; do test -f "$f" || { echo "missing $f"; exit 1; }; done
rm -rf "$B"; mkdir -p "$B"

SL=4.25; NF=128
X="-r 30 -c:v libx264 -crf 17 -preset medium -pix_fmt yuv420p"

# 1) animated shots + captions for the real-footage shots
for s in brand say andaza family end; do
  node scripts/render.cjs frames "$V/src/shots.html?shot=$s" "$B/anim_$s" $NF
  ffmpeg -v error -y -framerate 30 -i "$B/anim_${s}_%03d.png" -t $SL $X "$B/shot_$s.mp4"
done
for s in B C S R E; do
  node scripts/render.cjs frames "$V/src/chrome.html?seg=$s" "$B/ch_$s" 40
  ffmpeg -v error -y -framerate 30 -i "$B/ch_${s}_%03d.png" -vf "tpad=stop_mode=clone:stop_duration=$SL" -t $SL $X "$B/chrome_$s.mp4"
done

# 2) real footage inside the phone (screen 442x932 at 1234,74, 52px corners)
convert -size 442x932 xc:black -fill white -draw "roundrectangle 0,0 441,931 52,52" "$B/mask.png"
SHARP="scale=442:-2:flags=lanczos,crop=442:932:0:14,fps=30,format=rgba"
SOFT="scale=442:-2:flags=lanczos,crop=442:932:0:12,unsharp=5:5:0.6,fps=30,format=rgba"
OV="[2:v]format=gray[m];[f][m]alphamerge[fm];[0:v][fm]overlay=1234:74:shortest=1,format=yuv420p[v]"
real(){ # name start end
  ffmpeg -v error -y -i "$B/chrome_$1.mp4" -ss $2 -to $3 -i "$OLD" -loop 1 -i "$B/mask.png" \
    -filter_complex "[1:v]setpts=(PTS-STARTPTS)*$SL/($3-$2),$SHARP[f];$OV" -map "[v]" -t $SL $X "$B/shot_$1.mp4"; }
real B 2.0 8.6     # home -> Capture Recipe screen
real C 8.6 11.25   # tap Record, "Listening." (ends before any live text)
real S 42.0 53.8   # Transcribing / Reading spinners
ffmpeg -v error -y -i "$B/chrome_R.mp4" -ss 20.9 -to 24.6 -i "$NEW" -loop 1 -i "$B/mask.png" -ss 30.7 -to 32.9 -i "$NEW" -filter_complex \
  "[1:v]setpts=PTS-STARTPTS,fps=30[r1];[3:v]setpts=PTS-STARTPTS,fps=30[r2];[r1][r2]concat=n=2:v=1:a=0,setpts=PTS*$SL/5.9,$SOFT[f];$OV" \
  -map "[v]" -t $SL $X "$B/shot_R.mp4"   # Review screen + "Ingredients saved"
ffmpeg -v error -y -i "$B/chrome_E.mp4" -i "$V/src/assets/bhindi-recipe-clean.png" -loop 1 -i "$B/mask.png" -filter_complex \
  "[1:v]crop=1206:2543:0:0,scale=1768:3728:flags=lanczos,zoompan=z='1+0.045*on/$NF':x='iw/2-(iw/zoom/2)':y=0:d=$NF:s=442x932:fps=30,format=rgba[f];$OV" \
  -map "[v]" -t $SL $X "$B/shot_E.mp4"   # finished recipe, slow push-in

# 3) assemble on the grid: a cut every 4.0s
ORDER="brand B C say S andaza R E family end"
IN=""; for s in $ORDER; do IN="$IN -i $B/shot_$s.mp4"; done
FC=""; prev="[0:v]"; i=0; n=$(echo $ORDER | wc -w)
for s in $ORDER; do
  if [ $i -eq 0 ]; then i=1; continue; fi
  out="[x$i]"; [ $i -eq $((n-1)) ] && out="[vout]"
  FC="$FC${FC:+;}$prev[$i:v]xfade=transition=fade:duration=0.25:offset=$((i*4)).000$out"; prev=$out; i=$((i+1))
done
ffmpeg -v error -y $IN -filter_complex "$FC" -map "[vout]" $X -crf 18 "$B/video-silent.mp4"

# 4) audio: the music track if given, otherwise a silent track (some players want one)
OUT=$V/Samaan-Pantry-ProductHunt.mp4
if [ -n "${MUSIC:-}" ]; then
  DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$B/video-silent.mp4")
  ffmpeg -v error -y -i "$B/video-silent.mp4" -i "$MUSIC" -filter_complex \
    "[1:a]atrim=0:$DUR,afade=t=in:d=0.5,afade=t=out:st=$(awk "BEGIN{print $DUR-2.5}"):d=2.5[a]" \
    -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"
else
  ffmpeg -v error -y -i "$B/video-silent.mp4" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    -map 0:v -map 1:a -c:v copy -c:a aac -b:a 128k -shortest -movflags +faststart "$OUT"
fi
ffprobe -v error -show_entries format=duration -show_entries stream=codec_name,width,height -of default=nw=1 "$OUT"
echo "-> $ROOT/$OUT"
