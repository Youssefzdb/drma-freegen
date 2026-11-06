#!/bin/bash
# DRMA free-generation helper
# usage:
#   ./make_video.sh <count> "<prompt>" [path/to/fb_token.txt]
# output: .mp4 files in ./outputs/
set -u

API="https://drma.ai"
UA="Drma/200060 (Android)"
HDRS=(-H 'Content-Type: application/json' -H 'platform: web' -H 'version-code: 200060' -A "$UA")
FB_TOKEN_FILE="${3:-/tmp/fb_token.txt}"
COUNT="${1:-1}"
PROMPT="${2:-cinematic drone shot of a red sports car on a desert road at sunset, golden hour}"

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

gen_t2v() {        # $1 = token, $2 = prompt ; prints: <code>|<taskId>|<cost>
  local BODY
  BODY=$(python3 -c "
import json,sys
print(json.dumps({'prompt':sys.argv[1],'ratio':'16:9','modelBuildType':'t2v','duration':5,'resolution':480},separators=(',',':')))" "$2" 2>/dev/null) 
  [ -z "$BODY" ] && BODY='{"prompt":"","ratio":"16:9","modelBuildType":"t2v","duration":5,"resolution":480}'
  curl -sk -m 30 -X POST "$API/videoAi/aiGenerate/add/new" -H "token: $1" "${HDRS[@]}" -d "$BODY" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);q=d.get('data') or {};print(d.get('code'),q.get('id'),q.get('point'),sep='|')"
}

try_t2v() {        # $1 = token, $2 = prompt ; retried up to 3x, prints TASK id
  T="$1"; PROMPT="$2"
  for a in 1 2 3; do
    OUT=$(gen_t2v "$T" "$PROMPT")
    CODE=$(echo "$OUT" | cut -d'|' -f1)
    TASK=$(echo "$OUT" | cut -d'|' -f2)
    if [ "$CODE" = "0" ] && [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
      echo "$TASK"
      return 0
    fi
    if [ "$a" = "1" ]; then
      echo "  gen try$a code=$CODE (queued will retry)" >&2
    fi
    sleep 5
  done
  echo ""
  return 1
}

gen_t2i() {        # $1 = token, $2 = prompt ; prints: <code>|<taskId>|<cost>
  local BODY
  BODY=$(python3 -c "
import json,sys
print(json.dumps({'prompt':sys.argv[1],'modelBuildType':'t2i'},separators=(',',':')))" "$2" 2>/dev/null)
  [ -z "$BODY" ] && BODY='{"prompt":"","modelBuildType":"t2i"}'
  curl -sk -m 30 -X POST "$API/videoAi/aiGenerate/add/new" -H "token: $1" "${HDRS[@]}" -d "$BODY" \
    | python3 -c "import json,sys;d=json.load(sys.stdin);q=d.get('data') or {};print(d.get('code'),q.get('id'),q.get('point'),sep='|')"
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
  curl -skL -m 120 "$1" -o "outputs/$2.$ext"
  echo "saved outputs/$2.$ext"
}

made=0
n=0
while [ "$made" -lt "$COUNT" ]; do
  n=$((n+1))
  echo "### cycle $n"
  S=$(mint_session)
  UID_=$(echo "$S" | cut -d' ' -f1)
  T=$(echo "$S" | cut -d' ' -f2-)
  [ -z "$T" ] && { echo "  mint failed, retry"; continue; }
  P=$(get_points "$T")
  echo "  session=$UID_ credits=$P"

  if [ "$P" -ge 15 ]; then
    TASK=$(try_t2v "$T" "$PROMPT")
    echo "  gen_t2v task=$TASK"
    if [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
      URL=$(poll_task "$T" "$TASK")
      download "$URL" "video_${UID_}_${TASK}"
      made=$((made+1))
    fi
    P=$(get_points "$T"); echo "  credits after video=$P"
  fi

  # leftover free credits -> image (no extra cost)
  if [ "$P" -ge 10 ]; then
    OUT=$(gen_t2i "$T" "$PROMPT")
    TASK=$(echo "$OUT" | cut -d'|' -f2)
    if [ -n "$TASK" ] && [ "$TASK" != "None" ]; then
      URL=$(poll_task "$T" "$TASK")
      download "$URL" "img_${UID_}_${TASK}"
      echo "  bonus image saved"
    fi
  fi
done
echo "### done: $made video(s) in ./outputs/ ###"
