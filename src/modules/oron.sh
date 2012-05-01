#!/bin/bash
#
# oron.com module
# Copyright (c) 2012 krompospeed@googlemail.com
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

MODULE_ORON_REGEXP_URL="http://\(www\.\)\?\(oron\)\.com/[[:alnum:]]\{12\}"

MODULE_ORON_DOWNLOAD_OPTIONS="
AUTH_FREE,b:,auth-free:,USER:PASSWORD,Free account
LINK_PASSWORD,p:,link-password:,PASSWORD,Used in password-protected files"
MODULE_ORON_DOWNLOAD_RESUME=no
MODULE_ORON_DOWNLOAD_FINAL_LINK_NEEDS_COOKIE=no

MODULE_ORON_UPLOAD_OPTIONS="
AUTH_FREE,b:,auth-free:,USER:PASSWORD,Free account
TOEMAIL,,email-to:,EMAIL,<To> field for notification email
PRIVATE_FILE,,private,,Do not make file publicly accessable (account only)"
MODULE_ORON_UPLOAD_REMOTE_SUPPORT=yes

MODULE_ORON_DELETE_OPTIONS=""

# Switch language to english
# $1: cookie file
# stdout: nothing
oron_switch_lang() {
    curl -b "$1" -c "$1" -o /dev/null \
        'http://oron.com/?op=change_lang&lang=english' || return
}

# Static function. Proceed with login (free-membership or premium)
# $1: authentification
# $2: cookie file
# stdout: account type ("free" or "premium") on success
oron_login() {
    local AUTH_FREE=$1
    local COOKIE_FILE=$2
    local TYPE='free'
    local LOGIN_DATA HTML NAME

    LOGIN_DATA='login=$USER&password=$PASSWORD&op=login&redirect=&rand='
    HTML=$(post_login "$AUTH_FREE" "$COOKIE_FILE" "$LOGIN_DATA" \
       'http://oron.com/login' "-L -b $COOKIE_FILE") || return

    NAME=$(parse_cookie_quiet 'login' < "$COOKIE_FILE")
    [ -n "$NAME" ] || return $ERR_LOGIN_FAILED
    match 'Become a PREMIUM Member' "$HTML" || TYPE='premium' # bit of guessing...

    log_debug "Successfully logged in as $TYPE member ${NAME}."
    echo "$TYPE"
    return 0
}

# Generate a random decimal number
# $1: digits
# stdout: random number with $1 digits
oron_random_num() {
    local CC NUM DIGIT
    CC=0
    NUM=0

    while [ "$CC" -lt $1 ]; do
        DIGIT=$(($RANDOM % 10))
        NUM=$(($NUM * 10 + $DIGIT))
        (( CC++ ))
    done

    echo $NUM
}

# Determine whether checkbox/radio button with "name" attribute is checked.
# Note: "checked" attribute must be placed after "name" attribute.
#
# $1: name attribute of checkbox/radio button
# $2: (X)HTML data
# $? is zero on success
oron_is_checked() {
    matchi "<input.*name=[\"']\?$1[\"']\?.*[[:space:]]checked" "$2"
}

# Extract file id from download link
# $1: oron.com url
# stdout: file id
oron_extract_file_id() {
    local FILE_ID
    FILE_ID=$(echo "$1" | parse '.' 'oron\.com\/\([[:alnum:]]\{12\}\)') || return
    log_debug "File ID=$FILE_ID"
    echo "$FILE_ID"
}

# Output an oron.com file download URL
# $1: cookie file
# $2: oron.com url
# stdout: real file download link
#         file name
oron_download() {
    eval "$(process_options oron "$MODULE_ORON_DOWNLOAD_OPTIONS" "$@")"

    local COOKIE_FILE=$1
    local URL=$2
    local HTML SLEEP FILE_ID FILE_URL FILE_NAME REF METHOD DAYS HOURS MINS SECS
    local RND OPT_PASSWD

    FILE_ID=$(oron_extract_file_id "$URL") || return
    oron_switch_lang "$COOKIE_FILE" || return
    HTML=$(curl -b "$COOKIE_FILE" "$URL") || return

    # check the file for availability
    match 'File Not Found' "$HTML" && return $ERR_LINK_DEAD
    test "$CHECK_LINK" && return 0

    if [ -n "$AUTH_FREE" ]; then
        # ignore returned account type
        oron_login "$AUTH_FREE" "$COOKIE_FILE" > /dev/null || return
    fi

    # check, if file is special
    match 'Free Users can only download files sized up to' "$HTML" && \
        return $ERR_LINK_NEED_PERMISSIONS

    # extract properties
    FILE_NAME=$(echo "$HTML" | parse_form_input_by_name 'fname') || return
    REF=$(echo "$HTML" | parse_form_input_by_name 'referer') || return
    METHOD=$(echo "$HTML" | parse_form_input_by_name 'method_free' | \
        replace ' ' '+') || return
    log_debug "File name=$FILE_NAME"
    log_debug "Method=$METHOD"
    log_debug "Referer=$REF"

    # send download form
    HTML=$(curl -b "$COOKIE_FILE" \
        -F "op=download1" \
        -F "usr_login=" \
        -F "id=$FILE_ID" \
        -F "fname=$FILE_NAME" \
        -F "referer=$REF" \
        -F "method_free=$METHOD" \
        "$URL") || return

    # check for availability (yet again)
    match "File could not be found" "$HTML" && return $ERR_LINK_DEAD

    # check for file password protection
    if match 'Password:[[:space:]]*<input' "$HTML"; then
        log_debug "File is password protected"
        if [ -z "$LINK_PASSWORD" ]; then
            LINK_PASSWORD="$(prompt_for_password)" || return
        fi
        OPT_PASSWD="-F password=$LINK_PASSWORD"
    fi

    # retrieve waiting time
    DAYS=$(echo "$HTML" | parse_quiet '<p class="err">You have to wait' \
        ' \([[:digit:]]\+\) days\?')
    HOURS=$(echo "$HTML" | parse_quiet '<p class="err">You have to wait' \
        ' \([[:digit:]]\+\) hours\?')
    MINS=$(echo "$HTML" | parse_quiet '<p class="err">You have to wait' \
        ' \([[:digit:]]\+\) minutes\?')
    SECS=$(echo "$HTML" | parse_quiet '<p class="err">You have to wait' \
        ' \([[:digit:]]\+\) seconds\?')

    if [ -n "$DAYS" -o -n "$HOURS" -o -n "$MINS" -o -n "$SECS" ]; then
        [ -z "$DAYS" ]  && DAYS=0
        [ -z "$HOURS" ] && HOURS=0
        [ -z "$MINS" ]  && MINS=0
        [ -z "$SECS" ]  && SECS=0
        echo $(( ((($DAYS * 24) + $HOURS) * 60 + $MINS) * 60 + $SECS ))
        return $ERR_LINK_TEMP_UNAVAILABLE
    fi

    # retrieve random value
    RND=$(echo "$HTML" | parse_form_input_by_name "rand") || return
    log_debug "Random value: $RND"

    # retrieve sleep time
    # Please wait <span id="countdown">60</span> seconds
    SLEEP=$(echo "$HTML" | parse_tag 'Please wait' 'span') || return
    wait $((SLEEP + 1)) seconds || return

    # solve ReCaptcha
    local PUBKEY WCI CHALLENGE WORD ID DATA
    PUBKEY="6LdzWwYAAAAAAAzlssDhsnar3eAdtMBuV21rqH2N"
    WCI=$(recaptcha_process $PUBKEY) || return
    { read WORD; read CHALLENGE; read ID; } <<<"$WCI"

    # send captcha form (no double quote around $OPT_PASSWD)
    HTML=$(curl -b "$COOKIE_FILE" \
        -F "op=download2" \
        -F "id=$FILE_ID" \
        -F "rand=$RND" \
        -F "referer=$URL" \
        -F "method_free=$METHOD" \
        -F "method_premium=" \
        $OPT_PASSWD \
        -F "recaptcha_challenge_field=$CHALLENGE" \
        -F "recaptcha_response_field=$WORD" \
        -F "down_direct=1" \
        "$URL") || return

    # check for possible errors
    if match "Wrong captcha" "$HTML"; then
        log_error "Wrong captcha"
        captcha_nack $ID
        return $ERR_CAPTCHA
    elif match '<p class="err">Expired session</p>' "$HTML"; then
        echo 10 # just some arbitrary small value
        return $ERR_LINK_TEMP_UNAVAILABLE
    elif match "Download File</a></td>" "$HTML"; then
        log_debug "DL link found"
        FILE_URL=$(echo "$HTML" | parse_attr 'Download File' 'href') || return
    elif match 'Retype Password' "$HTML"; then
        log_error "Incorrect link password"
        return $ERR_LINK_PASSWORD_REQUIRED
    else
        log_error "No download link found. Site updated?"
        return $ERR_FATAL
    fi

    captcha_ack $ID

    echo "$FILE_URL"
    echo "$FILE_NAME"
}

# Upload a file to oron.com
# $1: cookie file
# $2: input file (with full path)
# $3: remote filename
# stdout: download link
#         delete link
oron_upload() {
    eval "$(process_options oron "$MODULE_ORON_UPLOAD_OPTIONS" "$@")"

    local COOKIE_FILE=$1
    local FILE=$2
    local DEST_FILE=$3
    local BASE_URL='http://oron.com'
    local SIZE HTML FORM SRV_ID SESS_ID SRV_URL RND FN ST
    local OPT_EMAIL MAX_SIZE ACCOUNT

    oron_switch_lang "$COOKIE_FILE" || return

    # login and set max file size (depends on account type)
    if [ -n "$AUTH_FREE" ]; then
        ACCOUNT=$(oron_login "$AUTH_FREE" "$COOKIE_FILE") || return

        case "$ACCOUNT" in
            free) # up to 1GB
                MAX_SIZE=$((1024*1024*1024))
                ;;
            premium) # up to 2GB
                MAX_SIZE=$((2048*1024*1024))
                ;;
            *)
                log_debug "Unknown account type '$ACCOUNT'."
                return $ERR_FATAL
                ;;
        esac
    else
        MAX_SIZE=$((400*1024*1024)) # up to 400MB

        [ -z "$PRIVATE_FILE" ] || \
            log_error 'option "--private" ignored, account only'
    fi

    if match_remote_url "$FILE"; then
        if [ -z "$ACCOUNT" ]; then
            log_error "Remote upload requires an account (free or premium)"
            return $ERR_LINK_NEED_PERMISSIONS
        fi
    else
        # file size seem to matter only for file upload
        SIZE=$(get_filesize "$FILE")
        if [ $SIZE -gt $MAX_SIZE ]; then
            log_error "File is too big, up to $MAX_SIZE bytes are allowed."
            return $ERR_FATAL
        fi
    fi

    HTML=$(curl -b "$COOKIE_FILE" "$BASE_URL") || return

    # gather relevant data from form
    FORM=$(grep_form_by_name "$HTML" 'file') || return
    SRV_ID=$(echo "$FORM" | parse_form_input_by_name 'srv_id') || return
    SESS_ID=$(echo "$FORM" | parse_form_input_by_name 'sess_id') || return
    SRV_URL=$(echo "$FORM" | parse_form_input_by_name 'srv_tmp_url') || return
    RND=$(oron_random_num 12)

    log_debug "Server ID: $SRV_ID"
    log_debug "Session ID: $SESS_ID"
    log_debug "Server URL: $SRV_URL"

    # prepare upload
    if match_remote_url "$FILE"; then
        HTML=$(curl -b "$COOKIE_FILE" \
            "$SRV_URL/status.html?url=$RND=$DEST_FILE") || return
    else
        HTML=$(curl -b "$COOKIE_FILE" \
            "$SRV_URL/status.html?file=$RND=$DEST_FILE") || return
    fi

    if ! match "You are oroning" "$HTML"; then
        log_error "Error uploading to server '$SRV_URL'."
        return $ERR_FATAL
    fi

    # upload file
    if match_remote_url "$FILE"; then
        HTML=$(curl -b "$COOKIE_FILE" \
            -F "srv_id=$SRV_ID" \
            -F "sess_id=$SESS_ID" \
            -F 'upload_type=url' \
            -F 'utype=reg' \
            -F "srv_tmp_url=$SRV_URL" \
            -F 'mass_upload=1' \
            -F "url_mass=$FILE" \
            -F "link_rcpt=$EMAIL" \
            -F 'link_pass=' \
            -F 'tos=1' \
            -F 'submit_btn= Upload! ' \
            "$SRV_URL/cgi-bin/upload_url.cgi/?X-Progress-ID=$RND") || return

        # gather relevant data
        FORM=$(grep_form_by_name "$HTML" 'F1' | break_html_lines) || return
        FN=$(echo "$FORM" | parse_tag 'fn' 'textarea') || return
        ST=$(echo "$FORM" | parse_tag 'st' 'textarea') || return

    else
        HTML=$(curl_with_log -b "$COOKIE_FILE" \
            -F 'upload_type=file' \
            -F "srv_id=$SRV_ID" \
            -F "sess_id=$SESS_ID" \
            -F "srv_tmp_url=$SRV_URL" \
            -F "file_0=@$FILE;type=application/octet-stream;filename=$DEST_FILE" \
            -F 'file_1=;filename=' \
            -F 'ut=file' \
            -F "link_rcpt=$EMAIL" \
            -F 'link_pass=' \
            -F 'tos=1' \
            -F 'submit_btn= Upload! ' \
            "$SRV_URL/upload/$SRV_ID/?X-Progress-ID=$RND") || return

        # gather relevant data
        FORM=$(grep_form_by_name "$HTML" 'F1' | break_html_lines_alt) || return
        FN=$(echo "$FORM" | parse_form_input_by_name 'fn') || return
        ST=$(echo "$FORM" | parse_form_input_by_name 'st') || return
    fi

    log_debug "FN: $FN"
    log_debug "ST: $ST"

    if [ "$ST" = "OK" ]; then
        log_debug 'Upload was successfull.'
    elif match 'banned by administrator' "$ST"; then
        log_error 'File is banned by admin.'
        return $ERR_FATAL
    elif match 'triggered our security filters' "$ST"; then
        log_error 'File is banned by security filter.'
        return $ERR_FATAL
    else
        log_error "Unknown upload state: $ST"
        return $ERR_FATAL
    fi

    [ -n "$TOEMAIL" ] && OPT_EMAIL="-F link_rcpt=$TOEMAIL"

    # get download url (no double quote around $OPT_EMAIL)
    HTML=$(curl -b "$COOKIE_FILE" \
        -F 'op=upload_result' \
        $OPT_EMAIL \
        -F "fn=$FN" \
        -F "st=$ST" \
        "$BASE_URL") || return

    local LINK DEL_LINK
    LINK=$(echo "$HTML" | parse_line_after 'Direct Link:' \
        'value="\([^"]*\)">') || return
    DEL_LINK=$(echo "$HTML" | parse_line_after 'Delete Link:' \
        'value="\([^"]*\)">') || return

    # do we need to edit the file? (change name/visibility)
    if [ -n "$ACCOUNT" -a -z "$PRIVATE_FILE" ] || \
        match_remote_url "$FILE" && [ "$DEST_FILE" != "dummy" ]; then
        log_debug 'Editing file...'

        local FILE_ID F_NAME F_PASS F_PUB
        FILE_ID=$(oron_extract_file_id "$LINK") || return

        # retrieve current values
        HTML=$(curl -b "$COOKIE_FILE" \
            "$BASE_URL/?op=file_edit;file_code=$FILE_ID") || return

        F_NAME=$(echo "$HTML" | parse_form_input_by_name 'file_name') || return
        F_PASS=$(echo "$HTML" | parse_form_input_by_name 'file_password') || return
        oron_is_checked 'file_public' "$HTML" && F_PUB='-F file_public=1'

        log_debug "Current name: $F_NAME"
        log_debug "Current pass: ${F_PASS//?/*}"
        [ -n "$F_PUB" ] && log_debug 'Currently public'

        match_remote_url "$FILE" && [ "$DEST_FILE" != "dummy" ] && F_NAME=$DEST_FILE
        [ -n "$ACCOUNT" -a -z "$PRIVATE_FILE" ] && F_PUB='-F file_public=1'

        # post changes (include HTTP headers to check for proper redirection;
        # no double quote around $F_PUB)
        HTML=$(curl -i -b "$COOKIE_FILE" \
            -F "file_name=$F_NAME" \
            -F "file_password=$F_PASS" \
            $F_PUB \
            -F 'op=file_edit' \
            -F "file_code=$FILE_ID" \
            -F 'save=+Submit+' \
            "$BASE_URL/?op=file_edit;file_code=$FILE_ID") || return

        HTML=$(echo "$HTML" | grep_http_header_location) || return
        match '?op=my_files' "$HTML" || log_error 'Could not edit file. Site update?'
    fi

    echo "$LINK"
    echo "$DEL_LINK"
}

# Delete a file on oron.com
# $1: cookie file
# $2: kill URL
oron_delete() {
    eval "$(process_options oron "$MODULE_ORON_DELETE_OPTIONS" "$@")"

    local COOKIEFILE=$1
    local URL=$2
    local HTML FILE_ID KILLCODE
    local BASE_URL='http:\/\/oron\.com'

    # check + parse URL
    FILE_ID=$(oron_extract_file_id "$URL") || return
    KILLCODE=$(echo "$URL" | parse . \
        "^$BASE_URL\/[[:alnum:]]\{12\}?killcode=\([[:alnum:]]\{10\}\)") || return
    log_debug "Killcode: $KILLCODE"

    oron_switch_lang "$COOKIEFILE" || return
    HTML=$(curl -b "$COOKIEFILE" -L "$URL") || return

    match "No such file exist" "$HTML" && return $ERR_LINK_DEAD

    HTML=$(curl -b "$COOKIEFILE" \
        -F "op=del_file" \
        -F "id=$FILE_ID" \
        -F "del_id=$KILLCODE" \
        -F "confirm=yes" \
        'http://oron.com') || return

    match 'File deleted successfully' "$HTML" || return $ERR_FATAL
}