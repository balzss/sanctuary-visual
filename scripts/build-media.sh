#!/usr/bin/env bash
# Turns original media into the optimized files the site serves from docs/assets.
# Source files can live anywhere; pass their path. Nothing here depends on a folder layout.
#
# Needs ffmpeg (libx264 + libsvtav1) and ImageMagick 7 with AVIF support.
# On macOS: brew install ffmpeg imagemagick
#
# USAGE
#   scripts/build-media.sh <command> [arguments]
#
# COMMANDS
#   still <image> [name]
#       Gallery still. Writes 640/1080/1600/2400 px AVIF + WebP (never upscaled) and a
#       1600 px JPG fallback to docs/assets/img/stills/. Prints the <li class="slide">
#       block to paste into the carousel in docs/index.html (add the alt text).
#
#   image <image> <name> <fallback-width> <width>...
#       Any responsive image: docs/assets/img/<name>-<width>.avif/.webp plus a JPG at
#       the fallback width. Example: image office.jpg studio 1000 800 1200
#
#   poster <video> <seconds> <name> [--portrait]
#       Still frame from a video as a responsive poster in docs/assets/img/posters/.
#       --portrait crops the centre 9:16 and writes <name>-portrait-<width>.
#
#   loop <video> <name>
#       Silent looping background (hero): 1080, 720 and portrait, H.264 + AV1,
#       plus landscape and portrait posters. Output: docs/assets/video/<name>-*.mp4
#
#   film <video> <name> [poster-seconds]
#       Full film with sound: 1080 (H.264 + AV1) and 720 (H.264), plus a poster.
#
#   social <video> <name>
#       Vertical clip, 720 px wide, H.264 + AV1, plus 480/720 px posters.
#       Name them social-1, social-2, ... to match the page.
#
#   icons [logo]       Favicon, .ico and Apple touch icon from a flat silhouette of the
#                      logo's alpha channel (default: grafikak/logo_white.png).
#   wordmark [logo]    Header/footer wordmark (default: grafikak/logo_white_transparent.png).
#   og <image> [logo]  1200x630 social share image: a still with the wordmark on it.
#   fonts              Re-downloads the self-hosted Archivo font files.
#
# EXAMPLES
#   scripts/build-media.sh still ~/renders/lobby.jpg
#   scripts/build-media.sh social ~/clips/street.mov social-5
#   scripts/build-media.sh film ~/clips/tour.mov film 50
#
# After adding media, reference the new files in docs/index.html. Video files are
# loaded by name from data-src (see assets/js/site.js). Set SITE=/some/dir to write
# somewhere other than docs/ (useful for testing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="${SITE:-$ROOT/docs}"
OUT="$SITE/assets"
IMG="$OUT/img"
VID="$OUT/video"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AVIF_Q=52
WEBP_Q=80
JPG_Q=82
STILL_WIDTHS=(640 1080 1600 2400)

die() { echo "error: $*" >&2; exit 1; }
need() { [[ -f "$1" ]] || die "file not found: $1"; }

# ---------- images ----------

# Writes <dest>-<w>.avif/.webp for each width (never upscaling) and <dest>-<fallback>.jpg.
# resp <source> <dest-prefix> <fallback-width> <width>...
resp() {
  local src="$1" dest="$2" fallback="$3"; shift 3
  local srcw; srcw=$(magick identify -format '%w' "$src[0]")
  mkdir -p "$(dirname "$dest")"
  local made=0
  for w in "$@"; do
    (( w > srcw )) && continue
    made=1
    magick "$src[0]" -alpha remove -alpha off -colorspace sRGB -filter Lanczos -resize "${w}x" \
      -unsharp 0x0.6+0.6+0.01 -strip "$TMP/r.png"
    magick "$TMP/r.png" -quality "$AVIF_Q" -define heic:speed=4 "$dest-$w.avif"
    magick "$TMP/r.png" -quality "$WEBP_Q" -define webp:method=6 "$dest-$w.webp"
  done
  if (( ! made )); then # every width is larger than the source: keep the source size
    magick "$src[0]" -alpha remove -alpha off -colorspace sRGB -strip "$TMP/r.png"
    magick "$TMP/r.png" -quality "$AVIF_Q" -define heic:speed=4 "$dest-$srcw.avif"
    magick "$TMP/r.png" -quality "$WEBP_Q" -define webp:method=6 "$dest-$srcw.webp"
  fi
  (( fallback > srcw )) && fallback=$srcw
  magick "$src[0]" -alpha remove -alpha off -colorspace sRGB -resize "${fallback}x" -strip \
    -sampling-factor 4:2:0 -interlace JPEG -quality "$JPG_Q" "$dest-$fallback.jpg"
  FALLBACK_W=$fallback
}

frame() { # frame <video> <seconds> <out.png>
  ffmpeg -v error -y -ss "$2" -i "$1" -frames:v 1 "$3"
}

# srcset <ext> <path-prefix> <url-prefix>: "url 640w, url 1080w" for the files that exist
srcset() {
  local ext="$1" prefix="$2" url="$3" f w
  local widths=()
  for f in "$prefix"-*."$ext"; do
    [[ -e "$f" ]] || continue
    w=${f##*-}; w=${w%.*}
    [[ "$w" =~ ^[0-9]+$ && "$f" == "$prefix-$w.$ext" ]] && widths+=("$w")
  done
  printf '%s\n' "${widths[@]}" | sort -n | awk -v u="$url" -v e="$ext" '{printf "%s%s-%s.%s %sw", (NR>1 ? ", " : ""), u, $1, e, $1}'
}

cmd_image() {
  [[ $# -ge 4 ]] || die "usage: image <image> <name> <fallback-width> <width>..."
  need "$1"
  local src="$1" name="$2"; shift 2
  resp "$src" "$IMG/$name" "$@"
  echo "wrote $IMG/$name-*"
}

cmd_still() {
  [[ $# -ge 1 ]] || die "usage: still <image> [name]"
  need "$1"
  local src="$1" name="${2:-}"
  if [[ -z "$name" ]]; then
    name=$(basename "${src%.*}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-' | sed 's/-*$//')
  fi
  local dest="$IMG/stills/$name"
  resp "$src" "$dest" 1600 "${STILL_WIDTHS[@]}"
  local dims; dims=$(magick identify -format 'width="%w" height="%h"' "$dest-$FALLBACK_W.jpg")
  local n; n=$(grep -c 'data-open=' "$SITE/index.html" 2>/dev/null || echo 0)
  local sizes='min(88vw, 107vh)' base="assets/img/stills/$name"
  cat <<EOF

Paste into the carousel in docs/index.html:

          <li class="slide">
            <button class="slide__btn" type="button" data-open="$n">
              <span class="visually-hidden">View full screen: </span>
              <picture>
                <source type="image/avif" sizes="$sizes" srcset="$(srcset avif "$dest" "$base")">
                <source type="image/webp" sizes="$sizes" srcset="$(srcset webp "$dest" "$base")">
                <img src="$base-$FALLBACK_W.jpg" $dims alt="DESCRIBE THE IMAGE" loading="lazy" decoding="async">
              </picture>
            </button>
          </li>
EOF
}

cmd_poster() {
  [[ $# -ge 3 ]] || die "usage: poster <video> <seconds> <name> [--portrait]"
  need "$1"
  frame "$1" "$2" "$TMP/frame.png"
  if [[ "${4:-}" == "--portrait" ]]; then
    local h w; h=$(magick identify -format '%h' "$TMP/frame.png"); w=$((h * 9 / 16))
    magick "$TMP/frame.png" -gravity center -crop "${w}x${h}+0+0" +repage "$TMP/portrait.png"
    resp "$TMP/portrait.png" "$IMG/posters/$3-portrait" "$w" "$w"
  else
    resp "$TMP/frame.png" "$IMG/posters/$3" 1280 960 1280 1920
  fi
  echo "wrote posters for $3"
}

# ---------- video ----------

COLOR=(-colorspace bt709 -color_primaries bt709 -color_trc bt709)

# h264 <src> <out> <filter> <crf> <maxrate> <audio-args...>
h264() {
  local src="$1" out="$2" vf="$3" crf="$4" max="$5"; shift 5
  echo "   $(basename "$out")"
  ffmpeg -v error -stats -y -i "$src" -vf "$vf,format=yuv420p" \
    -c:v libx264 -preset slow -crf "$crf" -maxrate "$max" -bufsize "$((${max%M} * 2))M" \
    -profile:v high -g 60 "${COLOR[@]}" "$@" -movflags +faststart "$out"
}

# av1 <src> <out> <filter> <crf> <audio-args...>
av1() {
  local src="$1" out="$2" vf="$3" crf="$4"; shift 4
  echo "   $(basename "$out")"
  ffmpeg -v error -stats -y -i "$src" -vf "$vf,format=yuv420p" \
    -c:v libsvtav1 -preset 5 -crf "$crf" -g 60 "${COLOR[@]}" "$@" -movflags +faststart "$out"
}

cmd_loop() {
  [[ $# -eq 2 ]] || die "usage: loop <video> <name>"
  need "$1"
  local src="$1" n="$2" portrait="crop=ih*9/16:ih,scale=608:1080:flags=lanczos"
  mkdir -p "$VID"
  h264 "$src" "$VID/$n-1080.mp4"          "scale=-2:1080:flags=lanczos" 25 3M -an
  av1  "$src" "$VID/$n-1080.av1.mp4"      "scale=-2:1080:flags=lanczos" 38 -an
  h264 "$src" "$VID/$n-720.mp4"           "scale=-2:720:flags=lanczos" 25 2M -an
  av1  "$src" "$VID/$n-720.av1.mp4"       "scale=-2:720:flags=lanczos" 38 -an
  h264 "$src" "$VID/$n-portrait.mp4"      "$portrait" 25 2M -an
  av1  "$src" "$VID/$n-portrait.av1.mp4"  "$portrait" 38 -an
  cmd_poster "$src" 0 "$n"
  cmd_poster "$src" 0 "$n" --portrait
}

cmd_film() {
  [[ $# -ge 2 ]] || die "usage: film <video> <name> [poster-seconds]"
  need "$1"
  local src="$1" n="$2"
  mkdir -p "$VID"
  h264 "$src" "$VID/$n-1080.mp4"     "scale=-2:1080:flags=lanczos" 23 5M -c:a aac -b:a 160k
  av1  "$src" "$VID/$n-1080.av1.mp4" "scale=-2:1080:flags=lanczos" 32 -c:a aac -b:a 160k
  h264 "$src" "$VID/$n-720.mp4"      "scale=-2:720:flags=lanczos" 24 3M -c:a aac -b:a 128k
  cmd_poster "$src" "${3:-1}" "$n"
}

cmd_social() {
  [[ $# -eq 2 ]] || die "usage: social <video> <name>"
  need "$1"
  local src="$1" n="$2"
  mkdir -p "$VID"
  h264 "$src" "$VID/$n.mp4"     "scale=720:-2:flags=lanczos" 26 2M -c:a aac -b:a 96k
  av1  "$src" "$VID/$n.av1.mp4" "scale=720:-2:flags=lanczos" 38 -c:a aac -b:a 96k
  frame "$src" 0 "$TMP/social.png"
  resp "$TMP/social.png" "$IMG/posters/$n" 480 480 720
}

# ---------- logos, icons, share image ----------

cmd_wordmark() {
  local logo="${1:-$ROOT/grafikak/logo_white_transparent.png}"; need "$logo"
  magick "$logo" -resize 640x -strip -define png:compression-level=9 "$IMG/wordmark.png"
  echo "wrote $IMG/wordmark.png"
}

cmd_icons() {
  local logo="${1:-$ROOT/grafikak/logo_white.png}"; need "$logo"
  # Flat silhouette of the mark (from its alpha), so small icons stay crisp instead of showing texture.
  magick "$logo" -alpha extract -resize 400% -threshold 35% -morphology Open Disk:4 -trim +repage "$TMP/mask.png"
  magick -size "$(magick identify -format '%wx%h' "$TMP/mask.png")" xc:'#f1ebe1' "$TMP/mask.png" \
    -compose CopyOpacity -composite "$TMP/shape.png"
  icon() { # icon <size> <shape-width> <out>
    magick -size 2048x2048 xc:'#0d0c0a' \( "$TMP/shape.png" -resize "${2}x${2}" \) \
      -gravity center -composite -resize "${1}x${1}" -depth 8 -strip "$3"
  }
  mkdir -p "$SITE"
  icon 180 1560 "$SITE/apple-touch-icon.png"
  icon 32 1760 "$SITE/favicon-32.png"
  icon 48 1760 "$TMP/icon-48.png"
  icon 16 1840 "$TMP/icon-16.png"
  magick "$TMP/icon-48.png" "$SITE/favicon-32.png" "$TMP/icon-16.png" "$SITE/favicon.ico"
  echo "wrote icons in $SITE"
}

cmd_og() {
  [[ $# -ge 1 ]] || die "usage: og <image> [logo]"
  need "$1"
  local logo="${2:-$ROOT/grafikak/logo_white_transparent.png}"; need "$logo"
  mkdir -p "$IMG"
  magick "$1" -resize 1200x630^ -gravity center -extent 1200x630 \
    \( -size 1200x630 gradient:'rgba(0,0,0,0)-rgba(0,0,0,0.65)' \) -composite \
    \( "$logo" -resize 560x \) -gravity southwest -geometry +56+56 -composite \
    -strip -quality 84 "$IMG/og.jpg"
  echo "wrote $IMG/og.jpg"
}

# ---------- fonts ----------

cmd_fonts() {
  mkdir -p "$OUT/fonts"
  local ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
  local css; css=$(curl -fsS -A "$ua" "https://fonts.googleapis.com/css2?family=Archivo:wdth,wght@100..125,300..800&display=swap")
  for subset in latin latin-ext; do
    local url
    url=$(printf '%s\n' "$css" | awk -v s="/* $subset */" '$0 == s {f=1} f && /src: url/ {match($0, /https:[^)]+/); print substr($0, RSTART, RLENGTH); exit}')
    curl -fsS "$url" -o "$OUT/fonts/archivo-$subset.woff2"
  done
  echo "wrote $OUT/fonts"
}

# ---------- dispatch ----------

command="${1:-}"; [[ $# -gt 0 ]] && shift
case "$command" in
  still)    cmd_still "$@" ;;
  image)    cmd_image "$@" ;;
  poster)   cmd_poster "$@" ;;
  loop)     cmd_loop "$@" ;;
  film)     cmd_film "$@" ;;
  social)   cmd_social "$@" ;;
  icons)    cmd_icons "$@" ;;
  wordmark) cmd_wordmark "$@" ;;
  og)       cmd_og "$@" ;;
  fonts)    cmd_fonts "$@" ;;
  ""|-h|--help|help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $command (run with --help)" ;;
esac
