#!/bin/bash
# Round 47: render the inner-voice EVALUATION SET with local macOS voices so
# they can be compared by ear. Usage:
#   tools/voice_samples.sh <out_dir> ["Voice A" "Voice B" ...]
# Without voice names it renders every installed Enhanced/Premium English
# voice plus the reference voices below. Local only (macOS `say`), no
# network. The game speaks thoughts only with an Enhanced/Premium voice
# (scripts/story/inner_voice.gd); everything else is captions.
set -e
OUT="${1:?usage: tools/voice_samples.sh <out_dir> [voices...]}"
shift || true
mkdir -p "$OUT"
LINES=(
  "ordinary|Good. That one's sorted."
  "confusion|Wait. Was that always on the list?"
  "concern|Nobody was logged in the tunnel. Nobody but me."
  "discomfort|My back is killing me. Too long at the panel."
  "fear|There's nobody out there."
)
if [ "$#" -gt 0 ]; then
  VOICES=("$@")
else
  VOICES=()
  while IFS= read -r v; do VOICES+=("$v"); done < <(say -v '?' | grep -E 'en_[A-Z]{2}' | grep -E '\((Premium|Enhanced)\)' | sed -E 's/ +en_[A-Z]{2}.*//')
  VOICES+=("Flo (English (US))" "Samantha" "Daniel" "Moira" "Karen" "Tessa")
fi
for v in "${VOICES[@]}"; do
  slug=$(echo "$v" | tr -c 'A-Za-z0-9' '_' | sed 's/_*$//')
  for l in "${LINES[@]}"; do
    tag="${l%%|*}"; text="${l#*|}"
    say -v "$v" -r 156 -o "$OUT/${slug}__${tag}.wav" --data-format=LEI16@22050 "$text"
  done
  echo "rendered: $v"
done
