#!/bin/bash
# Records the real-app footage for the App Store preview videos on an open iPhone 17 Pro Simulator.
# Usage: capture/record.sh AGENT_DEVICE_COMMAND LOCALE(en|ru) OUT_DIR [light|dark] [SLOW] [SCENES]
# SLOW multiplies the waits after animated steps; pass about 6 when the Simulator's slow animations are on
# (xcrun simctl spawn UDID notifyutil -s com.apple.UIKit.SimulatorSlowMotionAnimationState 1, then -p).
# SCENES is a space-separated subset of "home add person insights" (default: all).
# STORY=1 records variant D's story instead: You (Anton) give Grandpa Pavel a warm scarf back, without
# opening Details; the person scene opens Grandpa Pavel with one filter; no touch indicators are drawn.
# The Debug app must be installed; it is launched with the in-memory sample data, so nothing on the
# device changes. Each scene is its own clip: OUT_DIR/<locale>-<scene>.mp4.
set -euo pipefail

AD=$1
LOCALE=$2
OUT=$3
APPEARANCE=${4:-dark}
SLOW=${5:-1}
SCENES=" ${6:-home add person insights} "
pause() { sleep "$(python3 -c "print($1 * $SLOW)")"; }
want() { [[ "$SCENES" == *" $1 "* ]]; }
APP=pro.ziganshin.WhoGaveWhat
mkdir -p "$OUT"

if [ "$LOCALE" = ru ]; then
  LANG_ARGS=(--launch-args -AppleLanguages --launch-args "(ru)" --launch-args -AppleLocale --launch-args ru_RU
    --launch-args -preferredCurrencyCode --launch-args RUB)
  HOME_TAB="Главная"; PEOPLE_TAB="Люди"; INSIGHTS_TAB="Аналитика"; ADD_GIFT="Добавить подарок"
  ME="Антон"; FRIEND="Марина"; GIFT_NAME="Ароматическая свеча"; RECEIVED="Получено"; GIVEN="Подарено"; ALL="Все"
else
  LANG_ARGS=(--launch-args -AppleLanguages --launch-args "(en)" --launch-args -AppleLocale --launch-args en_US
    --launch-args -preferredCurrencyCode --launch-args USD)
  HOME_TAB="Home"; PEOPLE_TAB="People"; INSIGHTS_TAB="Insights"; ADD_GIFT="Add a gift"
  ME="Anton"; FRIEND="Marina"; GIFT_NAME="Scented candle"; RECEIVED="Received"; GIVEN="Given"; ALL="All"
fi
STORY=${STORY:-0}
PERSON="$ME"; FILTERS=("$RECEIVED" "$GIVEN" "$ALL"); DETAILS=1; TOUCHES=()
if [ "$STORY" = 1 ]; then
  if [ "$LOCALE" = ru ]; then FRIEND="Дедушка Павел"; GIFT_NAME="Тёплый шарф"; else FRIEND="Grandpa Pavel"; GIFT_NAME="Warm scarf"; fi
  PERSON="$FRIEND"; FILTERS=("$RECEIVED"); DETAILS=0; TOUCHES=(--hide-touches)
fi

"$AD" settings appearance "$APPEARANCE" >/dev/null
"$AD" open "$APP" --relaunch --launch-args -KS_SAMPLE_DATA --launch-args 1 "${LANG_ARGS[@]}" >/dev/null
sleep 2

# Anton becomes "Me", so the person page and Insights show the viewpoint. The viewpoint is a saved
# preference that outlives the in-memory sample data (KS_RESET_SELF is read only from the environment,
# which agent-device can't set), so a second recording on the same Simulator finds the switch already on:
# press it only when it is off, then confirm it is on.
"$AD" press "label=\"$PEOPLE_TAB\"" --settle >/dev/null
"$AD" press "label=\"$ME\"" --settle >/dev/null
if ! "$AD" is exists 'id="person-detail.is-me" value="1"' >/dev/null 2>&1; then
  "$AD" press 'id="person-detail.is-me"' --settle >/dev/null
fi
"$AD" wait 'id="person-detail.is-me" value="1"' >/dev/null
"$AD" back --settle >/dev/null
"$AD" press "label=\"$HOME_TAB\"" --settle >/dev/null
sleep 1

rec_start() { "$AD" record start "$OUT/$LOCALE-$1.mp4" --scope device ${TOUCHES[@]+"${TOUCHES[@]}"} >/dev/null; pause 1.2; }
rec_stop() { pause "${1:-1.5}"; "$AD" record stop >/dev/null; echo "recorded $OUT/$LOCALE-$2.mp4"; }

# 1. Home: the gift journal, a gentle scroll down and back.
if want home; then
rec_start home
pause 1.5
"$AD" scroll down 0.35 --duration-ms 1400 >/dev/null
pause 1.2
"$AD" scroll down 0.35 --duration-ms 1400 >/dev/null
pause 1.2
"$AD" swipe 200 250 200 750 >/dev/null
pause 0.6
"$AD" swipe 200 250 200 750 >/dev/null
rec_stop 1.5 home
fi

# 2. Add a gift: icon and price appear while typing, then giver, recipient, details and Save.
ref_of() { # n-th button whose label is "<row>, <value>" (From, then To) in the current form
  "$AD" snapshot -i 2>/dev/null | grep -E '\[button\] "[^"]+, [^"]+"' | sed -n "$1p" | grep -oE '@e[0-9]+' | head -1
}
if want add; then
rec_start add
pause 0.8
"$AD" press "label=\"$ADD_GIFT\"" >/dev/null
pause 1.4
"$AD" type "$GIFT_NAME" --delay-ms 120 >/dev/null
# The estimated price comes from the suggestion service a few seconds later; wait for it.
"$AD" wait text "≈" 20000 >/dev/null 2>&1 || true
pause 1.8
"$AD" type $'\n' >/dev/null
pause 0.8
FROM=$(ref_of 1)
"$AD" press "$FROM" >/dev/null
pause 1.3
"$AD" press "label=\"$ME\"" >/dev/null
pause 1.2
TO=$(ref_of 2)
"$AD" press "$TO" >/dev/null
pause 1.3
if ! "$AD" press "label=\"$FRIEND\"" >/dev/null 2>&1; then
  "$AD" scroll down 0.3 >/dev/null
  pause 1.0
  "$AD" press "label=\"$FRIEND\"" >/dev/null
fi
pause 1.2
if [ "$DETAILS" = 1 ]; then
  "$AD" press 'id="add-gift.details"' >/dev/null
  pause 1.8
fi
"$AD" press 'id="add-gift.save"' >/dev/null
rec_stop 2.5 add
fi

# 3. A person's history: received and given, with the filter.
if want person; then
rec_start person
pause 0.6
"$AD" press "label=\"$PEOPLE_TAB\"" >/dev/null
pause 1.3
"$AD" press "label=\"$PERSON\"" >/dev/null
pause 2.2
for F in "${FILTERS[@]}"; do
  "$AD" press "role=button label=\"$F\"" >/dev/null 2>&1 || true
  pause 1.6
done
rec_stop 1.2 person
fi

# 4. Insights: year summary, balance with each person, and the comparison.
if want insights; then
"$AD" back --settle >/dev/null 2>&1 || true
rec_start insights
pause 0.6
"$AD" press "label=\"$INSIGHTS_TAB\"" >/dev/null
pause 2.8
"$AD" scroll down 0.45 --duration-ms 1600 >/dev/null
pause 2.4
if [ "$STORY" = 1 ]; then
  # Compare You with Grandpa Pavel: one gift each way.
  "$AD" press 'id="insights.compare.b"' >/dev/null
  pause 1.6
  "$AD" press 'id="insights.picker.person.pavel"' >/dev/null
  pause 2.4
fi
rec_stop 0.5 insights
fi
rm -f "$OUT/.snap"
