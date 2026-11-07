#!/bin/bash
# DRMA generation helper — all creation modes
# usage:
#   ./make_video.sh <count> "<prompt>" [path/to/fb_token.txt] [mode] [source_image_url]
# modes:
#   t2v  (default) text→video     15 credits (5s 480p; 3pt/s @480, 6pt/s @720, max 15s)
#   i2v            image→video    15 credits   needs <source_image_url>
#   t2i            text→image     10 credits
#   i2i            image→image    10 credits   needs <source_image_url>
# output: .mp4 / .png files in ./outputs/
set -u

API="https://drma.ai"
UA="Drma/200060 (Android)"
HDRS=(-H 'Content-Type: application/json' -H 'platform: web' -H 'version-code: 200060' -A "$UA")
FB_TOKEN_FILE="${3:-/tmp/fb_token.txt}"
COUNT="${1:-1}"
PROMPT="${2:-cinematic drone shot of a red sports car on a desert road at sunset, golden hour}"
MODE="${4:-t2v}"
SRC_URL="${5:-}"

case "$MODE" in
  t2v|i2v|t2i|i2i) ;;
  *) echo "unknown mode '$MODE' (use: t2v i2v t2i i2i)"; exit 1 ;;
esac
case "$MODE" in
  story) echo "story runs through the microfilm flow (drama/v2 create + confirm) and is not a single add/new call"; exit 1 ;;
esac
case "$MODE" in
  i2v|i2i) [ -n "$SRC_URL" ] || { echo "mode $MODE needs source_image_url"; exit 1; } ;;
esac

# credits each mode needs per item
COST_T2V=15 COST_I2V=15 COST_T2I=10 COST_I2I=10
case "$MODE" in
  t2v) COST=$COST_T2V; OUTPREFIX="video" ;;
  i2v) COST=$COST_I2V; OUTPREFIX="i2v" ;;
  t2i) COST=$COST_T2I; OUTPREFIX="img" ;;
  i2i) COST=$COST_I2I; OUTPREFIX="img" ;;
esac

mkdir -p outputs
[ -s "$FB_TOKEN_FILE" ] || { echo "missing $FB_TOKEN_FILE (Firebase idToken)"; exit 1; }

b64() { python3 -c "import base64,sys;print(base64.b64encode(open('$1').read().strip().encode()).decode())"; }

mint_session() {   # prints: <userId> <signed token JSON>
  curl -sk -m 20 -X POST "$API/videoAi/user/oneClickLogin" "${HDRS[@]}" \
    -d "{\"idToken\":\"$(b64 "$FB_TOKEN_FILE")\"}" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);q=d.get('data') or {};print(q.get('userId'),q.get('token'))"
}

get_points() {     # $1 = token ; prints number
  curl -sk -m 15 "$API/videoAi/user/detail" -H "token: $1" "${HDRS[@]}" \
    | python3 -c "import json,sys;print(json.load(sys.stdin)['data'].get('point',0))"
}

# builds the JSON body for the chosen mode ($1 = token, $2 = prompt)
build_body() {
  python3 - "$MODE" "$2" "$SRC_URL" << 'PY'
import json, sys
mode, prompt, src = sys.argv[1], sys.argv[2], sys.argv[3]
if mode == "t2v":
    b = {"prompt":prompt,"ratio":"16:9","modelBuildType":"t2v","duration":5,"resolution":480}
elif mode == "i2v":
    b = {"prompt":prompt,"ratio":"16:9","modelBuildType":"i2v","duration":5,"resolution":480,"inputImageUrl":src}
elif mode == "t2i":
    b = {"prompt":prompt,"modelBuildType":"t2i"}
elif mode == "i2i":
    b = {"prompt":prompt,"modelBuildType":"i2i","inputImageUrlList":[src]}
else:
    sys.exit("unsupported mode")
print(json.dumps(b, separators=(',',':')))
PY
}

gen_item() {       # $1 = token, $2 = prompt ; prints: <code>|<taskId>|<cost>
  local BODY
  BODY=$(build_body "$1" "$2")
  curl -sk -m 30 -X POST "$API/videoAi/aiGenerate/add/new" -H "token: $1" "${HDRS[@]}" -d "$BODY" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);q=d.get('data') or {};print(d.get('code'),q.get('id'),q.get('point'),sep='|')"
}

try_gen() {        # $1 = token, $2 = prompt ; retried up to 3x, prints TASK id
  T="$1"; PROMPT="$2"
  for a in 1 2 3; do
    OUT=$(gen_item "$T" "$PROMPT")
    CODE=$(echo "$OUT" | cut -d'|' -f1)
    TASK=$(echo "$OUT" | cut -d'|' -f2)
    if [ "$CODE" = "0" ] && [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
      echo "$TASK"
      return 0
    fi
    if [ "$a" = "1" ]; then
      echo "  gen try$a code=$CODE (will retry)" >&2
    fi
    sleep 5
  done
  echo ""
  return 1
}

poll_task() {      # $1 = token, $2 = taskId ; waits until finished; prints URL
  T="$1"; ID="$2"
  for i in $(seq 1 16); do
    sleep 12
    R=$(curl -sk -m 20 "$API/videoAi/aiGenerate/$ID" -H "token: $T" "${HDRS[@]}")
    ST=$(echo "$R" | python3 -c "import json,sys;print(json.load(sys.stdin)['data'].get('status'))" 2>/dev/null)
    if [ "$ST" = "2" ]; then
      echo "$R" | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
u=d.get('outputVideoUrl') or d.get('outputImageUrl')
print(u or '')"
      return 0
    fi
  done
  echo ""
}

download() {       # $1 = url, $2 = out name
  [ -n "$1" ] || return
  ext="${1##*.}"
  curl -skL -m 180 "$1" -o "outputs/$2.$ext"
  echo "saved outputs/$2.$ext"
}

made=0
n=0
while [ "$made" -lt "$COUNT" ]; do
  n=$((n+1))
  echo "### cycle $n (mode=$MODE)"
  S=$(mint_session)
  UID_=$(echo "$S" | cut -d' ' -f1)
  T=$(echo "$S" | cut -d' ' -f2-)
  [ -z "$T" ] && { echo "  mint failed, retry"; continue; }
  P=$(get_points "$T")
  echo "  session=$UID_ credits=$P"

  if [ "$P" -ge "$COST" ]; then
    TASK=$(try_gen "$T" "$PROMPT")
    echo "  ${MODE} task=$TASK"
    if [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
      URL=$(poll_task "$T" "$TASK")
      download "$URL" "${OUTPREFIX}_${UID_}_${TASK}"
      made=$((made+1))
    fi
    P=$(get_points "$T"); echo "  credits after ${MODE}=$P"
  fi

  # leftover credits -> t2i image (no extra session needed)
  if [ "$P" -ge 10 ] && [ "$MODE" != "t2i" ] && [ "$MODE" != "i2i" ]; then
    OUT=$(gen_item "$T" "$PROMPT")   # body builder in t2i mode via temp override
    # simpler: dedicated t2i call
    OUT=$(python3 - << PY
import json
print(json.dumps({"prompt":"$PROMPT".replace('"','\\"'),"modelBuildType":"t2i"}))
PY
)
    TTI=$(curl -sk -m 30 -X POST "$API/videoAi/aiGenerate/add/new" -H "token: $T" "${HDRS[@]}" -d "$OUT" \
      | python3 -c "import json,sys;d=json.load(sys.stdin);q=d.get('data') or {};print(d.get('code'),q.get('id'),sep='|')")
    CODE=$(echo "$TTI" | cut -d'|' -f1); TASK=$(echo "$TTI" | cut -d'|' -f2)
    if [ "$CODE" = "0" ] && [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
      URL=$(poll_task "$T" "$TASK")
      download "$URL" "img_${UID_}_${TASK}"
      echo "  bonus image saved"
    fi
  fi
done
echo "### done: $made item(s) in ./outputs/ ###"
