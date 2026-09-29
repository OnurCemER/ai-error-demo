#!/usr/bin/env bash
# GitHub REST API ile issue ve pull request olusturma.
# Git push/fetch icin ayri bir auth sarmalayicisina gerek yok: origin SSH
# uzerinden (~/.ssh/config'teki github.com IdentityFile ile) kimlik
# dogruluyor, git komutlari normal sekilde cagrilir.

# github_owner -> GITHUB_REPO'nun (owner/repo) owner kismi
github_owner() {
    echo "${GITHUB_REPO%%/*}"
}

# github_create_issue EXCEPTION_CLASS MESSAGE ENDPOINT STACK_TRACE
# Basarili olursa yeni issue numarasini stdout'a yazar.
github_create_issue() {
    local cls="$1" msg="$2" endpoint="$3" stack="$4"
    local title="${cls##*.}: ${msg}"
    title="${title:0:250}"

    local body
    body=$(printf '### Hata Bilgisi\n\n- **Endpoint:** `%s`\n- **Exception:** `%s`\n- **Mesaj:** %s\n\n### Stack Trace\n```\n%s\n```' \
                  "$endpoint" "$cls" "$msg" "$stack")

    local payload
    payload=$(jq -n --arg title "$title" --arg body "$body" '{title:$title, body:$body, labels:["bug"]}')

    local resp http_status_code resp_body
    resp="$(http_request POST "${GITHUB_BASE_URL}/repos/${GITHUB_REPO}/issues" "$GITHUB_TOKEN" "$payload")"
    http_status_code="$(http_status "$resp")"
    resp_body="$(http_body "$resp")"

    if [ "$http_status_code" != "201" ]; then
        echo "[watch-errors] GitHub issue olusturulamadi (HTTP $http_status_code): $resp_body" >&2
        return 1
    fi
    echo "$resp_body" | jq -r '.number'
}

# github_find_pr BRANCH_NAME
# Basariyla bulunursa PR JSON'unu ({number,url}) stdout'a yazar, yoksa bos doner.
github_find_pr() {
    local branch="$1"
    local resp http_status_code body
    resp="$(http_request GET \
        "${GITHUB_BASE_URL}/repos/${GITHUB_REPO}/pulls?head=$(github_owner):${branch}&state=all" \
        "$GITHUB_TOKEN")"
    http_status_code="$(http_status "$resp")"
    body="$(http_body "$resp")"
    [ "$http_status_code" = "200" ] || return 1

    local pr
    pr="$(echo "$body" | jq -c '.[0] // empty')"
    [ -z "$pr" ] && return 1
    echo "$pr" | jq -c '{number: .number, url: .html_url}'
}

# github_create_pr BRANCH_NAME TITLE BODY
# Basariyla olusturursa ya da zaten varsa PR JSON'unu ({number,url}) stdout'a yazar.
github_create_pr() {
    local branch="$1" title="$2" body_text="$3"
    local payload
    payload=$(jq -n --arg title "$title" --arg body "$body_text" \
        --arg head "$branch" --arg base "dev" \
        '{title:$title, body:$body, head:$head, base:$base}')

    local resp http_status_code resp_body
    resp="$(http_request POST "${GITHUB_BASE_URL}/repos/${GITHUB_REPO}/pulls" "$GITHUB_TOKEN" "$payload")"
    http_status_code="$(http_status "$resp")"
    resp_body="$(http_body "$resp")"

    if [ "$http_status_code" = "201" ]; then
        echo "$resp_body" | jq -c '{number: .number, url: .html_url}'
    elif [ "$http_status_code" = "422" ]; then
        echo "[watch-errors] Bu branch icin zaten bir PR var, mevcut PR kullaniliyor." >&2
        github_find_pr "$branch"
    else
        echo "[watch-errors] GitHub PR olusturulamadi (HTTP $http_status_code): $resp_body" >&2
        return 1
    fi
}
