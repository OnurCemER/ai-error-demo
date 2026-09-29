#!/usr/bin/env bash
# Spring Boot uygulamasindan gelen hatalari izler; her hata icin otomatik
# olarak GitHub'da bir issue acar, AI (opencode, basarisizsa claude fallback)
# ile kodu duzeltir, yeni bir bugfix branch'inde commit'ler, GitHub'a push
# eder (SSH) ve dev branch'ine bir Pull Request acar.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${PROJECT_DIR}/logs/error.log"
TMP_DIR="${PROJECT_DIR}/.watch-tmp"
LOCK_FILE="${TMP_DIR}/watch.lock"

MODEL="${AI_MODEL:-litellm/deepseek-ai/DeepSeek-V4-Flash}"
OPENCODE_TIMEOUT="${OPENCODE_TIMEOUT:-90}"

GITHUB_BASE_URL="${GITHUB_BASE_URL:-https://api.github.com}"

mkdir -p "$TMP_DIR"
touch "$LOG_FILE"

# shellcheck source=lib/http.sh
source "${PROJECT_DIR}/lib/http.sh"
# shellcheck source=lib/state.sh
source "${PROJECT_DIR}/lib/state.sh"
# shellcheck source=lib/common.sh
source "${PROJECT_DIR}/lib/common.sh"
# shellcheck source=lib/github.sh
source "${PROJECT_DIR}/lib/github.sh"

state_init

# ---------------------------------------------------------------------------
# Onkosul kontrolleri: demo ortasinda degil, hemen basta hata ver.
# ---------------------------------------------------------------------------
preflight_fail=0

for cmd in jq curl git mvn opencode; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[watch-errors] HATA: '$cmd' bulunamadi, kurulu olmali." >&2
        preflight_fail=1
    fi
done

for var in GITHUB_REPO GITHUB_TOKEN; do
    if [ -z "${!var:-}" ]; then
        echo "[watch-errors] HATA: '$var' ortam degiskeni ayarlanmamis." >&2
        preflight_fail=1
    fi
done

origin_url="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
if [ -z "$origin_url" ]; then
    echo "[watch-errors] HATA: 'origin' remote'u tanimli degil. README'deki tek seferlik kurulumu once yapin." >&2
    preflight_fail=1
fi

if [ "$preflight_fail" = "1" ]; then
    echo "[watch-errors] Onkosullar saglanmadi, cikiliyor." >&2
    exit 1
fi

echo "[watch-errors] Onkosul kontrolleri basarili. Model: $MODEL"

PROMPT_TEMPLATE='Bir Spring Boot uygulamasinda gercek bir hata olustu. Asagida
tam exception bilgisi ve stack trace var. Gorevin:
1) Stack trace icindeki dosya/satir bilgisine bakarak hatanin GERCEK kok
   nedenini kaynak kodda (src/main/java altinda) bul.
2) Kaynak koddaki ilgili Java dosyasini DUZENLE (gercekten dosyayi degistir,
   sadece aciklama yazma) ve minimal, dogru bir duzeltme uygula (orn. eksik
   null-check ekle, eksik konfigurasyon/fallback mantigini duzelt).
3) Degisikligi kisaca ozetle.
4) Cevabinin EN BASINDA tek bir satirda su formatta yaz:
   TR_OZET: <hatanin ne oldugunu anlatan kisa Turkce cumle>
   Sonra normal aciklamani/ozetini yaz.
Asla yeni bir exception sinifi ekleme ya da sorunu try/catch ile bastirma;
gercek kok nedeni duzelt.

STACK TRACE BLOCK:
%s'

process_block() {
    local blockfile="$1"
    local block_content
    block_content="$(cat "$blockfile")"

    echo "=================================================================="
    echo "[watch-errors] YENI HATA YAKALANDI:"
    echo "------------------------------------------------------------------"
    cat "$blockfile"
    echo "=================================================================="

    if [ -e "$LOCK_FILE" ]; then
        echo "[watch-errors] Onceki AI cagrisi hala calisiyor, bu blok atlandi."
        rm -f "$blockfile"
        return
    fi
    touch "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' RETURN

    local cls msg endpoint stack sig
    cls="$(extract_field "$blockfile" EXCEPTION_CLASS)"
    msg="$(extract_field "$blockfile" MESSAGE)"
    endpoint="$(extract_field "$blockfile" ENDPOINT)"
    stack="$(extract_stack_trace "$blockfile")"
    sig="$(compute_signature "$blockfile")"

    echo "[watch-errors] Hata imzasi: $sig"

    # Not: degisken adi bilerek "pipeline_status" (duz "status" degil) -
    # zsh'de $status, $?'nin salt-okunur bir takma adidir; bu script bash
    # shebang'iyla calisir ama olasi bir isim carpismasini onceden onlemek
    # icin degisken bilerek boyle adlandirildi.
    local issue_number="" branch_name="" pipeline_status=""
    if state_has "$sig"; then
        issue_number="$(state_get "$sig" issue_number)"
        branch_name="$(state_get "$sig" branch)"
        pipeline_status="$(state_get "$sig" status)"
        echo "[watch-errors] Bu hata daha once islenmis (Issue: #$issue_number, durum: $pipeline_status). Devam ediliyor..."
    fi

    # ---- 1) GitHub issue (yoksa olustur) ----
    if [ -z "$issue_number" ]; then
        echo "[watch-errors] GitHub issue olusturuluyor..."
        issue_number="$(github_create_issue "$cls" "$msg" "$endpoint" "$stack")" || {
            echo "[watch-errors] GitHub issue olusturulamadi, blok atlaniyor." >&2
            rm -f "$blockfile"
            return
        }
        echo "[watch-errors] GitHub issue olusturuldu: https://github.com/${GITHUB_REPO}/issues/${issue_number}"
        branch_name="bugfix/${issue_number}-$(short_slug "$cls")"
        pipeline_status="issue_created"
        state_set "$sig" "$(jq -n --arg n "$issue_number" --arg br "$branch_name" --arg st "$pipeline_status" \
            '{issue_number:$n, branch:$br, status:$st}')"
    fi

    echo "[watch-errors] Branch: $branch_name"

    # ---- 2) Kirli calisma agaci korumasi ----
    local current_branch
    current_branch="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD)"
    if [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]; then
        if [ "$current_branch" = "$branch_name" ]; then
            echo "[watch-errors] $branch_name uzerinde yarim kalmis degisiklik var, devam ediliyor."
        else
            echo "[watch-errors] UYARI: calisma agaci beklenmedik sekilde kirli (dal: $current_branch). Bu blok atlaniyor; elle 'git status' kontrol edin." >&2
            rm -f "$blockfile"
            return
        fi
    fi

    # ---- 3) prod/dev fetch + bugfix branch olustur/checkout ----
    echo "[watch-errors] origin/prod ve origin/dev fetch ediliyor..."
    git -C "$PROJECT_DIR" fetch origin prod dev

    if git -C "$PROJECT_DIR" show-ref --verify --quiet "refs/heads/$branch_name"; then
        git -C "$PROJECT_DIR" checkout "$branch_name"
    elif git -C "$PROJECT_DIR" ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; then
        git -C "$PROJECT_DIR" checkout -b "$branch_name" "origin/$branch_name"
    else
        git -C "$PROJECT_DIR" checkout -b "$branch_name" origin/prod
    fi

    # ---- 4) AI duzeltmesi + derleme kapisi + commit (henuz yapilmamissa) ----
    if [[ "$pipeline_status" != "fix_committed" && "$pipeline_status" != "pushed" && "$pipeline_status" != "pr_created" ]]; then
        local prompt ai_output_file
        prompt="$(printf "$PROMPT_TEMPLATE" "$block_content")"
        ai_output_file="$(mktemp "${TMP_DIR}/ai_output.XXXXXX")"

        run_ai_fix "$prompt" "$ai_output_file"

        echo "[watch-errors] Kaynak kod derleniyor (mvn compile)..."
        if ! (cd "$PROJECT_DIR" && mvn -q compile); then
            echo "[watch-errors] UYARI: AI duzeltmesi derlenemedi. Commit yapilmadi, elle mudahale gerekli." >&2
            rm -f "$blockfile" "$ai_output_file"
            return
        fi

        local tr_ozet detay commit_msg_file
        tr_ozet="$(extract_tr_ozet "$ai_output_file" "$cls")"
        detay="$(extract_detay "$ai_output_file")"
        commit_msg_file="$(mktemp "${TMP_DIR}/commitmsg.XXXXXX")"
        {
            printf 'fix: %s\n\n' "$tr_ozet"
            printf 'Yapilan Degisiklik:\n%s\n\n' "$detay"
            printf 'Refs: #%s\n' "$issue_number"
        } > "$commit_msg_file"

        git -C "$PROJECT_DIR" add -A
        git -C "$PROJECT_DIR" commit -F "$commit_msg_file"
        rm -f "$ai_output_file" "$commit_msg_file"

        pipeline_status="fix_committed"
        state_set "$sig" "$(jq -n --arg st "$pipeline_status" '{status:$st}')"
    else
        echo "[watch-errors] Fix zaten commit'lenmis, mevcut branch icin derleme senkronize ediliyor..."
        (cd "$PROJECT_DIR" && mvn -q compile) || true
    fi

    echo "[watch-errors] Devtools restart'i bekleniyor... (spring-boot terminaline bakin)"

    # ---- 5) Push (henuz yapilmamissa) ----
    if [[ "$pipeline_status" != "pushed" && "$pipeline_status" != "pr_created" ]]; then
        echo "[watch-errors] Branch GitHub'a push ediliyor (SSH)..."
        git -C "$PROJECT_DIR" push origin "$branch_name"
        pipeline_status="pushed"
        state_set "$sig" "$(jq -n --arg st "$pipeline_status" '{status:$st}')"
    fi

    # ---- 6) PR olustur/bul (henuz yapilmamissa) ----
    if [ "$pipeline_status" != "pr_created" ]; then
        echo "[watch-errors] GitHub'da PR araniyor/olusturuluyor..."
        local title body_text pr pr_url
        title="fix: #${issue_number} icin otomatik duzeltme (${cls##*.})"
        body_text="$(printf 'Otomatik AI duzeltmesi.\n\nCloses #%s' "$issue_number")"

        pr="$(github_find_pr "$branch_name")"
        if [ -z "$pr" ]; then
            pr="$(github_create_pr "$branch_name" "$title" "$body_text")"
        fi

        if [ -n "$pr" ]; then
            pr_url="$(echo "$pr" | jq -r '.url')"
            echo "[watch-errors] PR hazir: $pr_url"
            state_set "$sig" "$(jq -n --arg st "pr_created" --arg url "$pr_url" '{status:$st, pr_url:$url}')"
        else
            echo "[watch-errors] UYARI: PR olusturulamadi/bulunamadi. Elle kontrol edin." >&2
        fi
    fi

    echo "[watch-errors] Ozet: Issue=https://github.com/${GITHUB_REPO}/issues/${issue_number}  Branch=${branch_name}"
    rm -f "$blockfile"
}

echo "[watch-errors] ${LOG_FILE} izleniyor..."

tail -F -n0 "$LOG_FILE" | \
awk -v tmpdir="$TMP_DIR" '
    /===AI_ERROR_START===/ { buf=""; capturing=1 }
    capturing { buf = buf $0 "\n" }
    /===AI_ERROR_END===/ {
        if (capturing) {
            seq++
            outfile = tmpdir "/block_" seq ".txt"
            print buf > outfile
            close(outfile)
            print outfile
            fflush(stdout)
        }
        capturing = 0
    }
' | \
while IFS= read -r blockfile; do
    process_block "$blockfile"
done
