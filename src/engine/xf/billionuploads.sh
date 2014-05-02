#!/bin/bash
#
# billionuploads callbacks
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

xfcb_billionuploads_ul_parse_result() {
    local PAGE=$1

    local STATE FILE_CODE

    FILE_CODE=$(parse 'fc-X-x-' 'fc-X-x-\([^"]\+\)' <<< "$PAGE")
    STATE=$(parse 'st-X-x-' 'st-X-x-\([^"]\+\)' <<< "$PAGE")

    echo "$STATE"
    echo "$FILE_CODE"
}

xfcb_billionuploads_dl_parse_form2() {
    xfcb_generic_dl_parse_form2 "$@" '' '' '' '' '' '' '' '' '' \
        'geekref=yeahman' || return
}

xfcb_billionuploads_dl_parse_final_link() {
    local PAGE=$1
    #local FILE_NAME=$2

    local FILE_URL

    local CRYPT

    if ! match '<span subway="metro">' "$PAGE"; then
        log_error "Unexpected content."
        return $ERR_FATAL
    fi

    log_debug 'Decoding final link...'

    CRYPT=$(parse 'subway="metro"' 'subway="metro">[^<]*XXX\([^<]\+\)XXX[^<]*' <<< "$PAGE") || return
    if ! match '^[[:alnum:]=]\+$' "$CRYPT"; then
        log_error "Something wrong with encoded message."
        return $ERR_FATAL
    fi

    FILE_URL=$(echo "$CRYPT" | base64 -d | base64 -d)

    echo "$FILE_URL"
}