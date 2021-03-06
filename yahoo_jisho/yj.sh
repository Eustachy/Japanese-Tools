#!/bin/bash
# Copyright: Christoph Dittmann <github@christoph-d.de>
# License: GNU GPL, version 3 or later; http://www.gnu.org/copyleft/gpl.html
#
# This script performs a Yahoo dictionary lookup for Japanese words.
#

. "$(dirname "$0")"/../gettext/gettext.sh

MAX_TITLE_LENGTH=60
MAX_RESULT_LENGTH=120

set -u

# Accumulate all parameters
QUERY="$*"
# Restrict length
QUERY=${QUERY:0:100}

if [[ ! ${URL-} ]]; then
    echo_ "Please don't run this script directly."
    exit 1
fi

if [[ $QUERY = 'help' || $QUERY = '' ]]; then
    printf_ 'Example: %s' "$IRC_COMMAND 車　くるま"
    echo_ 'Providing the reading is optional. If it is missing, it will be guessed by mecab.'
    exit 0
fi

# Split query into kanji and reading part.
KANJI=$(printf '%s' "$QUERY" | \
    sed 's#[ 　/／・[［「【〈『《].*##' | \
    sed 's#[　 ]##g')
READING=$(printf '%s' "$QUERY" | \
    sed 's#^[^ 　/／・[［「【〈『《]*.\(.*\)$#\1#' | \
    sed 's#[] 　／・［「【〈『《］」】〉』》]##g')

# If the reading is empty, ask mecab.
if [[ ! $READING ]]; then
    READING=$(printf '%s\n' "$KANJI" | \
        mecab --node-format="%f[7]" --eos-format= --unk-format=%m)
fi

QUERY="$KANJI【$READING】"

fix_html_entities() {
    sed "s/\&\#39;/'/g" |
    sed 's/\&lt;/</g' |
    sed 's/\&gt;/>/g' |
    sed 's/\&quot;/"/g' |
    sed 's/\&amp;/\&/g' |
    sed 's/\&nbsp;/ /g'
}
# Creates a tinyurl from $1.
make_tinyurl() {
    [[ ${NO_TINY_URL-} ]] || wget 'http://tinyurl.com/api-create.php?url='"$(encode_query "$1")" \
        --quiet -O - --timeout=5 --tries=1
}
# URL encoding.
encode_query() {
    # Escape single quotes for use in perl
    local ENCODED_QUERY=${1//\'/\\\'}
    ENCODED_QUERY=$(perl -MURI::Escape -e "print uri_escape('$ENCODED_QUERY');")
    printf '%s\n' "$ENCODED_QUERY"
}
ask_dictionary() {
    local URL="$URL$(encode_query "$1")"
    local SOURCE
    SOURCE=$(wget "$URL" --quiet -O - --timeout=10 --tries=1)
    if [[ $? -ne 0 ]]; then
        echo_ 'A network error occured.'
        return
    fi
    local TITLE=$(printf '%s' "$SOURCE" | \
        grep -A 1 -m 1 '^<div class="title-keyword">$' | \
        tail -n 1 | \
        sed 's#<[^>]*>##g' | \
        sed 's#\([0-9]\+\)#(\1)#g' | \
        fix_html_entities)
    local DEFINITION=$(printf '%s' "$SOURCE" | \
        grep -A 3 -m 1 '^<table class="d-detail">$' | \
        tail -n 1 | \
        sed 's#\[下接語\].*$##' | \
        sed 's#^[[「【〈『《『][^<]*\(<br>\)*##' | \
        sed 's#《[^》]*》##g' | \
        perl -pe 's#<table><tr valign="top" align="left" num="3">(.*?)</table>#\1#g' | \
        perl -pe 's#［([0-9]+)］#\1　#g' | \
        perl -pe 's#<br>→.*?(<br>→.*?)*<br>#<br>#g' | \
        perl -pe 's#<table.*?</table>##g' | \
        perl -pe 's#<a.*?>(.*?)</a>#\1#g' | \
        perl -pe 's#<br><img.*?>(.*?)<br>#<br>#g' | \
        sed 's#<br>\(<br>\)\?#\n#g' | \
        sed 's#<[^>]*>##g' | \
        fix_html_entities)
    DEFINITION="${DEFINITION//$'\n'$'\n'/$'\n'}"
    [[ ! $DEFINITION ]] && return
    printf '%s\n' "${TITLE:0:$MAX_TITLE_LENGTH} ( $( make_tinyurl "$URL" ) )"
    printf '%s\n' "${DEFINITION//$'\n'/   }"
}

RESULT=$(ask_dictionary "$QUERY")

if [[ ! $RESULT ]]; then
    echo "見つかりませんでした。"
    exit 0
fi

# Print title line.
printf '%s\n' "$RESULT" | head -n 1

# Cut off title line.
RESULT=$(printf '%s\n' "$RESULT" | tail -n +2)

# Restrict length if necessary.
if [[ ${#RESULT} -ge $(( $MAX_RESULT_LENGTH - 3 )) ]]; then
    RESULT="${RESULT:0:$(( $MAX_RESULT_LENGTH - 3 ))}"
    RESULT=$(printf '%s\n' "$RESULT")...
fi

# Print main result.
printf '%s\n' "$RESULT"

exit 0
