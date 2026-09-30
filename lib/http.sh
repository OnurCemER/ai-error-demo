#!/usr/bin/env bash
# GitHub REST API cagrilari icin ortak curl sarmalayicisi.

# http_request METHOD URL TOKEN [JSON_BODY]
# Stdout: response body, ardindan son satirda "HTTP_STATUS:<kod>".
http_request() {
    local method="$1" url="$2" token="$3" body="${4:-}"

    local args=(-sS -X "$method"
        -H "Accept: application/vnd.github+json"
        -H "Authorization: Bearer $token"
        -H "X-GitHub-Api-Version: 2022-11-28"
        -H "Content-Type: application/json; charset=UTF-8"
        -w '\nHTTP_STATUS:%{http_code}')

    if [ -n "${CURL_CA_BUNDLE:-}" ]; then
        args+=(--cacert "$CURL_CA_BUNDLE")
    fi
    if [ "${INSECURE_TLS:-0}" = "1" ]; then
        echo "[watch-errors] UYARI: INSECURE_TLS=1 - TLS sertifika dogrulamasi KAPALI!" >&2
        args+=(-k)
    fi
    if [ -n "$body" ]; then
        args+=(-d "$body")
    fi

    curl "${args[@]}" "$url"
}

# http_status RESPONSE -> HTTP durum kodunu ayiklar
http_status() {
    echo "$1" | grep '^HTTP_STATUS:' | tail -1 | cut -d: -f2
}

# http_body RESPONSE -> HTTP_STATUS satiri haric govdeyi verir
http_body() {
    echo "$1" | sed '$d'
}
