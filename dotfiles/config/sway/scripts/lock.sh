#!/bin/sh

IMAGE=/tmp/swaylock.png
LOCK=/home/evan/nix/dotfiles/config/sway/scripts/lock.png
LOCKARGS=""
BLURTYPE="0x6"

for OUTPUT in `swaymsg -t get_outputs | jq -r '.[] | select(.active == true) | .name'`
do
  IMAGE=/tmp/$OUTPUT-lock.png
  grim -o $OUTPUT $IMAGE
  convert $IMAGE -blur $BLURTYPE $IMAGE
  composite -gravity center $LOCK $IMAGE $IMAGE
  LOCKARGS="${LOCKARGS} -f -i ${OUTPUT}:${IMAGE}"
  IMAGES="${IMAGES} ${IMAGE}"
done
swaylock $LOCKARGS
rm $IMAGES
