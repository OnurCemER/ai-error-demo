#!/usr/bin/env bash
# Spring Boot uygulamasindan gelen hatalari izler, opencode (fallback: claude)
# ile otomatik olarak analiz edip kaynak kodu duzeltir.
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${PROJECT_DIR}/logs/error.log"
TMP_DIR="${PROJECT_DIR}/.watch-tmp"
LOCK_FILE="${TMP_DIR}/watch.lock"
MODEL="${AI_MODEL:-litellm/moonshotai/Kimi-K2.7-Code}"
OPENCODE_TIMEOUT="${OPENCODE_TIMEOUT:-90}"

mkdir -p "$TMP_DIR"
touch "$LOG_FILE"

PROMPT_TEMPLATE='Bir Spring Boot uygulamasinda gercek bir hata olustu. Asagida
tam exception bilgisi ve stack trace var. Gorevin:
1) Stack trace icindeki dosya/satir bilgisine bakarak hatanin GERCEK kok
   nedenini kaynak kodda (src/main/java altinda) bul.
2) Kaynak koddaki ilgili Java dosyasini DUZENLE (gercekten dosyayi degistir,
   sadece aciklama yazma) ve minimal, dogru bir duzeltme uygula (orn. eksik
   null-check ekle, eksik konfigurasyon/fallback mantigini duzelt).
3) Degisikligi kisaca ozetle.
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

    local prompt
    prompt="$(printf "$PROMPT_TEMPLATE" "$block_content")"

    local opencode_ok=1
    if [ "${SKIP_OPENCODE:-0}" = "1" ]; then
        echo "[watch-errors] SKIP_OPENCODE=1, opencode atlanip dogrudan claude kullanilacak."
        opencode_ok=0
    else
        echo "[watch-errors] opencode cagriliyor (model: $MODEL, timeout: ${OPENCODE_TIMEOUT}s)..."
        # --dir bayragi bu ortamda WSL yollarini yanlis yorumluyor ("Failed to
        # change directory"); bunun yerine calisma dizinine cd ediliyor. Bazi
        # ucretsiz litellm modelleri cok yavas/tutarsiz yanit verebiliyor (canli
        # demoda gozlendi: dakikalar surebiliyor), o yuzden sinirli bir sure
        # sonra vazgecip claude fallback'ine geciliyor. Demo gunu opencode
        # yavassa SKIP_OPENCODE=1 ile dogrudan claude'a gecilebilir.
        if (cd "$PROJECT_DIR" && timeout "${OPENCODE_TIMEOUT}s" opencode run "$prompt" \
                --model "$MODEL" \
                --agent build \
                --format default); then
            echo "[watch-errors] opencode basariyla tamamlandi."
        else
            opencode_ok=0
        fi
    fi

    if [ "$opencode_ok" = "0" ]; then
        echo "[watch-errors] opencode basarisiz oldu ya da zaman asimina ugradi, claude CLI fallback deneniyor..."
        if (cd "$PROJECT_DIR" && claude -p "$prompt" \
                --dangerously-skip-permissions \
                --add-dir "$PROJECT_DIR" \
                --output-format text < /dev/null); then
            echo "[watch-errors] claude fallback basariyla tamamlandi."
        else
            echo "[watch-errors] claude fallback da basarisiz oldu. Manuel inceleme gerekiyor."
        fi
    fi

    echo "[watch-errors] Kaynak kod derleniyor (mvn compile)..."
    (cd "$PROJECT_DIR" && mvn -q compile)

    echo "[watch-errors] Devtools restart'i bekleniyor... (spring-boot terminaline bakin)"

    rm -f "$blockfile" "$LOCK_FILE"
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
