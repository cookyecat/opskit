#!/usr/bin/env bash
# Build a standalone C/C++ OpenCV program using pkg-config.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: opencv.sh SOURCE.{c,cc,cpp,cxx} [OUTPUT]
Compile one source file using OpenCV 4 (fallback: legacy opencv).

Examples:
  ./opencv.sh demo.cpp
  ./opencv.sh "examples/video capture.cpp" /tmp/capture-demo

Requires pkg-config and the OpenCV development libraries.
CC and CXX environment variables override the default compilers.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage; exit 0
fi
if [[ $# -lt 1 || $# -gt 2 || ! -f "$1" ]]; then
  usage >&2; exit 2
fi

source_file="$1"
output_file="${2:-${source_file%.*}}"
case "$source_file" in
  *.c)
    compiler="${CC:-cc}"
    language_flags=() ;;
  *.cc|*.cpp|*.cxx)
    compiler="${CXX:-c++}"
    language_flags=(-std=c++17) ;;
  *)
    echo "Only .c, .cc, .cpp or .cxx inputs are supported." >&2
    exit 2 ;;
esac

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "pkg-config is missing." >&2; exit 1
fi
if pkg-config --exists opencv4; then
  package=opencv4
elif pkg-config --exists opencv; then
  package=opencv
else
  echo "OpenCV development package not found (opencv4/opencv)." >&2
  exit 1
fi

# pkg-config emits whitespace-separated compiler/linker flags.
read -r -a cflags <<< "$(pkg-config --cflags "$package")"
read -r -a libs <<< "$(pkg-config --libs "$package")"

"$compiler" "${language_flags[@]}" "${cflags[@]}" "$source_file" \
  -o "$output_file" "${libs[@]}"
printf 'Built: %s\n' "$output_file"
