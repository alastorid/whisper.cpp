#!/usr/bin/env bash
# shellcheck disable=2086

# MIT License

# Copyright (c) 2022 Daniils Petrovs
# Copyright (c) 2023 Jennifer Capasso

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Small shell script to get spoken text from youtube VODs.
# This uses YT-DLP, ffmpeg and the CPP version of Whisper: https://github.com/ggerganov/whisper.cpp
#
# Sample usage:
#
#   git clone https://github.com/ggerganov/whisper.cpp
#   cd whisper.cpp
#   make
#   ./examples/yt-txt.sh https://www.youtube.com/watch?v=1234567890
#

set -Eeuo pipefail

# get script file location
if command -v realpath > /dev/null 2>&1; then
    SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
fi
SCRIPT_DIR="${SCRIPT_PATH%/*}"

################################################################################
# Documentation on downloading models can be found in the whisper.cpp repo:
# https://github.com/ggerganov/whisper.cpp/#usage
#
# note: unless a multilingual model is specified, WHISPER_LANG will be ignored
# and the video will be transcribed as if the audio were in the English language
################################################################################
MODEL_NAME="ggml-large-v3-turbo"
MODEL_PATH="${MODEL_PATH:-${SCRIPT_DIR}/../models/${MODEL_NAME}.bin}"

################################################################################
# Where to find the whisper.cpp executable.  default to the examples directory
# which holds this script in source control
################################################################################
WHISPER_EXECUTABLE="${WHISPER_EXECUTABLE:-${SCRIPT_DIR}/../build/bin/whisper-cli}";

# Set to desired language to be translated into Chinese
WHISPER_LANG="${WHISPER_LANG:-Chinese}";

# Default to 4 threads (this was most performant on my 2020 M1 MBP)
WHISPER_THREAD_COUNT="${WHISPER_THREAD_COUNT:-4}";

msg() {
    echo >&2 -e "${1-}"
}

cleanup() {
    local -r clean_me="${1}";

    if [ -d "${clean_me}" ]; then
      msg "Cleaning up...";
      rm -rf "${clean_me}";
    else
      msg "'${clean_me}' does not appear to be a directory!";
      exit 1;
    fi;
}

check_requirements() {
    if ! command -v ffmpeg &>/dev/null; then
        echo "ffmpeg is required: https://ffmpeg.org";
        exit 1
    fi;

    if ! command -v yt-dlp &>/dev/null; then
        echo "yt-dlp is required: https://github.com/yt-dlp/yt-dlp";
        exit 1;
    fi;

    if ! command -v "${WHISPER_EXECUTABLE}" &>/dev/null; then
        echo "The C++ implementation of Whisper is required: https://github.com/ggerganov/whisper.cpp"
        echo "Sample usage:";
        echo "";
        echo "  git clone https://github.com/ggerganov/whisper.cpp";
        echo "  cd whisper.cpp";
        echo "  make";
        echo "  ./examples/yt-wsp.sh https://www.youtube.com/watch?v=1234567890";
        echo "";
        exit 1;
    fi;

}
init () {
    pip install ane_transformers
    pip install openai-whisper
    pip install coremltools
    ${SCRIPT_DIR}/../models/generate-coreml-model.sh ${MODEL_NAME}
    # Build whisper using CMake
    # cmake -B build -DWHISPER_COREML=1
    # cmake --build build -j --config Release
}
check_requirements;

################################################################################
# for now we only take one argument
# TODO: a for loop
################################################################################
source_url="${1}"
# https://.../...v=ABC123
# v = ABC123
v="${source_url#*v=}"
v="${v%%&*}"
out_file_name="yt${v}"
out_txt="${out_file_name}.txt"
# Check if the input is a file or a URL
if [ -f "$source_url" ]; then
    # Input is a file
    file_name=$(basename -- "$source_url")
    out_file_name="${file_name%.*}"
    out_txt="${out_file_name}.txt"

    if [ ! -f "$out_txt" ]; then
        ffmpeg -hide_banner -loglevel error -i "$source_url" \
            -ar 16000 -ac 1 -c:a pcm_s16le -f wav - \
        | "$WHISPER_EXECUTABLE" -bs 6 -np -fa -m "$MODEL_PATH" -l "$WHISPER_LANG" -f - -t "$WHISPER_THREAD_COUNT" | tee "$out_txt"
    fi
else
    VIDEO_ID=${v}
    URL="https://www.youtube.com/watch?v=${VIDEO_ID}"
    TITLE=$(yt-dlp --get-title --cookies-from-browser safari "$URL")
    UPLOAD_DATE=$(yt-dlp --print upload_date --cookies-from-browser safari "$URL")
    FORMATTED_DATE=$(date -j -f "%Y%m%d" "$UPLOAD_DATE" +"%Y.%m.%d")

    if [ ! -f ${out_txt} ] ; then
        yt-dlp -f "bestaudio[ext=m4a]" --cookies-from-browser safari -q --no-warnings --no-part -o - "${URL}" \
            | ffmpeg -hide_banner -loglevel error -i - \
                  -ar 16000 -ac 1 -c:a pcm_s16le -f wav - \
            | "${WHISPER_EXECUTABLE}" -bs 6 -np -fa -m "${MODEL_PATH}" -l "${WHISPER_LANG}" -f - -t "${WHISPER_THREAD_COUNT}" | tee ${out_txt}
    fi
fi
