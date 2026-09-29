#!/usr/bin/env bash
# Hata blogundan alan cikarma, signature/slug helper'lari ve AI duzeltme cagrisi.

# poll_tail FILE
# "tail -F -n0"'a alternatif: dosyanin buyudugu her seferinde sadece YENI
# baytlari basar (eski icerigi tekrar oynatmaz), sonsuza kadar calisir.
# stat() tabanli polling kullanir, inotify'a guvenmez - cunku WSL'de bir
# Windows surecinin /mnt/c altinda yazdigi degisiklikler icin inotify
# olaylari WSL tarafina hic ulasmiyor (gozlemlendi: uygulama IntelliJ'den
# Windows'ta calisirken tail -F hicbir zaman yeni satirlari yakalamiyordu,
# --disable-inotify da bu coreutils derlemesinde mevcut degil). Bu fonksiyon
# hem WSL-icinden hem Windows-tarafindan yazilan dosyalarda calisir.
poll_tail() {
    local file="$1"
    local last_size
    last_size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
    while true; do
        local cur_size
        cur_size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
        if [ "$cur_size" -gt "$last_size" ]; then
            tail -c "+$((last_size + 1))" "$file"
            last_size="$cur_size"
        elif [ "$cur_size" -lt "$last_size" ]; then
            # dosya kucaldi (reset/truncate edildi), bastan basla
            last_size=0
        fi
        sleep 1
    done
}

# extract_field BLOCKFILE FIELD_NAME
extract_field() {
    grep -m1 "^$2: " "$1" | sed "s/^$2: //"
}

# extract_stack_trace BLOCKFILE
extract_stack_trace() {
    sed -n '/^STACK_TRACE:$/,/^===AI_ERROR_END===$/p' "$1" | sed '1d;$d'
}

# compute_signature BLOCKFILE -> 12 hex karakterlik kimlik
# EXCEPTION_CLASS + com.demo.aierror icindeki ilk stack frame'e dayanir:
# kod gercekten duzelmeden ayni satir tekrar hata veremeyeceginden, ayni
# signature'in tekrar gorunmesi "henuz duzelmedi, ayni olay" anlamina gelir.
compute_signature() {
    local cls first_frame
    cls="$(extract_field "$1" EXCEPTION_CLASS)"
    first_frame="$(grep -m1 -E '^[[:space:]]*at com\.demo\.aierror' "$1" | sed 's/^[[:space:]]*at //')"
    printf '%s|%s' "$cls" "$first_frame" | sha256sum | cut -c1-12
}

# short_slug EXCEPTION_CLASS -> kisa, url/branch-uyumlu slug
# orn: java.lang.NullPointerException -> null-pointer-exception
short_slug() {
    local simple="${1##*.}"
    echo "$simple" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

# run_ai_fix PROMPT OUTPUT_FILE -> AI cagrisinin (opencode, basarisizsa claude
# fallback) tum stdout/stderr cikisini OUTPUT_FILE'a yazar ve terminale de
# akitir (canli demo gorunurlugu icin), basari/basarisizlik donduru.
run_ai_fix() {
    local prompt="$1" output_file="$2"
    local opencode_ok=1

    if [ "${SKIP_OPENCODE:-0}" = "1" ]; then
        echo "[watch-errors] SKIP_OPENCODE=1, opencode atlanip dogrudan claude kullanilacak."
        opencode_ok=0
    else
        # Kok neden bulundu: opencode.json'daki litellm hub'i
        # (aihub-api.turktelekom.com.tr) kurumsal, kendinden imzali bir
        # sertifika kullaniyor. Node.js bunu varsayilan olarak reddediyor;
        # bu da her istekte anlik TLS hatasina ve (SDK'nin ic tekrar deneme
        # mantigi yuzunden) dakikalarca suren gecikmelere/timeout'lara yol
        # aciyordu (gozlemlendi: 90s timeout, hatta bir seferinde ~11 dakika).
        # NODE_EXTRA_CA_CERTS ile kurumsal CA'yi Node'un guven deposuna
        # eklemek bunu tamamen cozuyor (dogrulandi: 90s+ -> ~9s).
        local opencode_ca_bundle="${OPENCODE_CA_BUNDLE:-$HOME/.config/corporate-ca/turktelekom-ca-bundle.pem}"
        if [ -f "$opencode_ca_bundle" ]; then
            export NODE_EXTRA_CA_CERTS="$opencode_ca_bundle"
        fi

        echo "[watch-errors] opencode cagriliyor (model: $MODEL, timeout: ${OPENCODE_TIMEOUT}s)..."
        # --dir bayragi bu ortamda WSL yollarini yanlis yorumluyor ("Failed to
        # change directory"); bunun yerine calisma dizinine cd ediliyor.
        if (cd "$PROJECT_DIR" && timeout "${OPENCODE_TIMEOUT}s" opencode run "$prompt" \
                --model "$MODEL" \
                --agent build \
                --format default 2>&1 | tee "$output_file"); then
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
                --output-format text < /dev/null 2>&1 | tee "$output_file"); then
            echo "[watch-errors] claude fallback basariyla tamamlandi."
        else
            echo "[watch-errors] claude fallback da basarisiz oldu. Manuel inceleme gerekiyor."
            return 1
        fi
    fi
    return 0
}

# extract_tr_ozet AI_OUTPUT_FILE EXCEPTION_CLASS -> commit'in "Hata Aciklamasi"
# satiri (commit subject'i). AI'nin ciktisinda "TR_OZET:" etiketli satiri
# arar, yoksa jenerik bir varsayilana duser. Git commit subject konvansiyonuna
# uymasi icin sert bir uzunluk siniri da uygulanir (AI talimati gormezden
# gelse bile).
extract_tr_ozet() {
    local tr_ozet
    tr_ozet="$(grep -m1 '^TR_OZET:' "$1" | sed 's/^TR_OZET: *//')"
    if [ -z "$tr_ozet" ]; then
        tr_ozet="${2##*.} hatasi duzeltildi"
    fi
    if [ "${#tr_ozet}" -gt 72 ]; then
        tr_ozet="${tr_ozet:0:69}..."
    fi
    echo "$tr_ozet"
}

# extract_tr_detay AI_OUTPUT_FILE -> commit'in "Yapilan Degisiklik" govdesi.
# AI'nin ciktisindaki TR_DETAY_START/TR_DETAY_END arasindaki kisa ozeti
# kullanir (ham/uzun AI ciktisini degil) - ANSI kodlari ve bos satirlar
# temizlenir, guvenlik icin uzunluk yine de sinirlanir. Blok yoksa jenerik
# bir varsayilana duser.
extract_tr_detay() {
    local detay
    detay="$(sed -n '/^TR_DETAY_START$/,/^TR_DETAY_END$/p' "$1" \
        | sed '1d;$d' \
        | sed -e 's/\x1b\[[0-9;]*m//g' \
        | sed -e '/^[[:space:]]*$/d' \
        | head -c 800)"
    if [ -z "$detay" ]; then
        detay="Kaynak kodda tespit edilen kok neden AI tarafindan duzeltildi."
    fi
    echo "$detay"
}
