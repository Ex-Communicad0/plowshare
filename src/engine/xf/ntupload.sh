#!/bin/bash
#
# ntupload callbacks
# Copyright (c) 2014 Plowshare team
#
# This file is part of Plowshare.
#
# Plowshare is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Plowshare is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Plowshare.  If not, see <http://www.gnu.org/licenses/>.

xfcb_ntupload_dl_commit_step1() {
    local -r COOKIE_FILE=$1
    local -r FORM_ACTION=$2
    local -r FORM_DATA=$3

    local PAGE FILE_ID

    # www.ntupload.to special, but can be used on some sites with embedded videos enabled
    # For example we can detect media type avi|mp4|flv|wmv... and then try to get embed version.
    # Some sites (like ntupload.to) add captcha and timers to get video, but return the same
    #  player block as in embed version. But we connot get filename from embed version. That's
    #  why I placed this after first form parser.
    FILE_ID=$(parse . '/\([[:alnum:]]\{12\}\)' <<< "$FORM_ACTION")
    PAGE=$(curl "$BASE_URL/embed-$FILE_ID.html") || return

    echo "$PAGE"
}

xfcb_ntupload_dl_parse_streaming() {
    local PAGE=$1
    local -r URL=$2
    local -r FILE_NAME=$3

    local FILE_URL

    [ -z $FILE_NAME ] && return 1

    FILE_URL=$(parse '^var urlvar' "urlvar='\([^']\+\)" <<< "$PAGE")
    echo "$FILE_URL"
    echo "$FILE_NAME"
    return 0
}

xfcb_ntupload_pr_parse_file_size() {
    local -r PAGE=$1
    local FILE_SIZE

    FILE_SIZE=$(parse_tag_quiet '^<p>[0-9.]\+[[:space:]]*[KMGBb]\+</p>$' 'p' <<< "$PAGE")

    echo "$FILE_SIZE"
}