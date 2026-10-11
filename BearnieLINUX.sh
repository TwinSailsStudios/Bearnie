#!/bin/sh
printf '\033c\033]0;%s\a' Bearnie
base_path="$(dirname "$(realpath "$0")")"
"$base_path/BearnieLINUX.x86_64" "$@"
