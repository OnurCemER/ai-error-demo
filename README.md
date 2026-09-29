# ai-error-demo

Yapay zeka destekli otomatik olay-yönetimi (incident response) demosu: bir
Spring Boot uygulamasında fırlatılan hatayı ayrı bir izleyici script
(`watch-errors.sh`) yakalar ve tamamen otomatik olarak:

1. **GitHub'da** (`github.com/OnurCemER/ai-error-demo`) bir issue açar,
2. **opencode** (litellm modelleri, fallback: **Claude Code CLI**) ile kaynak
   koddaki gerçek kök nedeni bulup düzeltir,
3. Düzeltmeyi `prod`'dan açılan yeni bir `bugfix/*` branch'inde conventional-commit
   formatıyla commit'ler,
4. Branch'i **GitHub'a SSH üzerinden** push eder,
5. `dev` branch'ine bir **Pull Request** açar (issue'yu `Closes #N` ile otomatik kapatacak şekilde).

Spring Boot DevTools sayesinde düzeltme sonrası uygulama otomatik yeniden
başlar, böylece "butona bas → hata → GitHub issue → AI fix → PR" döngüsü
canlı olarak izlenebilir.

## Gerekli araçlar

`jq`, `curl`, `git`, `mvn`, `opencode` kurulu ve PATH'te olmalı. `jq` yoksa:
```bash
sudo apt-get install -y jq
```
(`jq` gerekli — GitHub'a gönderilen JSON body'ler Java exception
mesajları/AI çıktısı gibi çift tırnak/newline içerebilen metinler taşıyor;
bunu elle escape etmek yerine `jq -n --arg` güvenli JSON üretimi sağlıyor.)

`watch-errors.sh` başlangıçta bu araçları ve aşağıdaki ortam değişkenlerini
kontrol eder; biri eksikse **demo ortasında değil, hemen başta** açık bir
hata mesajıyla çıkar.

## Ortam değişkenleri

| Değişken | Varsayılan | Zorunlu | Not |
|---|---|---|---|
| `AI_MODEL` | `litellm/deepseek-ai/DeepSeek-V4-Flash` | hayır | |
| `OPENCODE_TIMEOUT` | `90` | hayır | saniye; süre aşılırsa `claude` fallback'i devreye girer |
| `SKIP_OPENCODE` | - | hayır | `1` = opencode'u atla, direkt `claude` kullan |
| `GITHUB_BASE_URL` | `https://api.github.com` | hayır | GitHub Enterprise kullanılıyorsa değiştirin |
| `GITHUB_REPO` | - | **evet** | `owner/repo` formatında, örn. `OnurCemER/ai-error-demo` |
| `GITHUB_TOKEN` | - | **evet** | Fine-grained PAT (Issues+PR+Contents: Read&Write yeterli), asla sohbete/koda yapıştırılmaz |
| `CURL_CA_BUNDLE` | - | hayır | kurumsal iç CA sertifikası PEM yolu (bkz. TLS notu) |
| `INSECURE_TLS` | `0` | hayır | `1` = TLS doğrulamasını kapatır (`-k`), her çağrıda uyarı basar — sadece son çare |
| `OPENCODE_CA_BUNDLE` | `~/.config/corporate-ca/turktelekom-ca-bundle.pem` | hayır | litellm hub'ının (Node.js/opencode için) kurumsal CA'sı — dosya varsa otomatik `NODE_EXTRA_CA_CERTS` olarak kullanılır |

`GITHUB_TOKEN`'ı kendi shell profilinizde (`~/.bashrc`/`~/.zshrc`) veya demo
öncesi `export` ile ayarlayın; hiçbir zaman bu script'lere veya bir sohbete
yapıştırmayın. **Not:** git push/fetch işlemleri `GITHUB_TOKEN`'ı kullanmaz —
onlar SSH üzerinden, aşağıdaki deploy key ile kimlik doğrular. `GITHUB_TOKEN`
sadece Issue/PR REST API çağrıları için gerekli.

## Tek seferlik kurulum

### 1) SSH erişimi (yapıldı)
Bu ortamda GitHub'a giden SSH (port 22) trafiği kurumsal ağ tarafından
filtreleniyor; GitHub'ın resmi **443 üzerinden SSH** alternatifi kullanıldı.
`~/.ssh/config`:
```
Host github.com
    Hostname ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/ai_error_demo_github
    IdentitiesOnly yes
```
Bu demoya özel, parolasız, ayrı bir SSH anahtarı (`~/.ssh/ai_error_demo_github`)
oluşturuldu ve repoya **deploy key** (write access) olarak eklendi — kullanıcının
genel hesap anahtarı hiç kullanılmadı, blast radius sadece bu repo ile sınırlı.

### 2) Repo baseline'ı (yapıldı)
```bash
git remote add origin git@github.com:OnurCemER/ai-error-demo.git
git branch -m master prod
git push -u origin prod
git checkout -b dev prod
git push -u origin dev
git checkout prod
```

### 3) GitHub token
[Settings → Developer settings → Fine-grained tokens](https://github.com/settings/personal-access-tokens/new)'dan
sadece `ai-error-demo` reposuna erişimi olan, **Issues: Read&Write**,
**Pull requests: Read&Write**, **Contents: Read&Write** izinli bir token
oluşturun. `export GITHUB_TOKEN=...` ile kendi terminalinizde ayarlayın.

### 4) TLS — GitHub (genelde gerekmez)
`api.github.com`/`github.com` public CA'larla imzalı olduğundan normalde
ekstra bir şey gerekmez. Bir kurumsal proxy/MITM cihazı araya giriyorsa:
```bash
export CURL_CA_BUNDLE=/path/to/corporate-ca-bundle.pem
```

### 5) TLS — litellm hub / opencode (yapıldı, gerekli)
`opencode.json`'daki litellm endpoint'i (`aihub-api.turktelekom.com.tr`)
kurumsal, kendinden imzalı bir sertifika kullanıyor. Node.js bunu varsayılan
olarak reddediyor — bu da her istekte anlık TLS hatasına ve (SDK'nin iç
tekrar deneme mantığı yüzünden) **dakikalarca süren gecikmelere/timeout'lara**
yol açıyordu (gözlemlendi: 90s timeout'a takılma, bir seferinde ~11 dakika).
Kurumsal CA'yı çıkarıp Node'un güven deposuna ekleyin:
```bash
mkdir -p ~/.config/corporate-ca
echo | openssl s_client -connect aihub-api.turktelekom.com.tr:443 -showcerts 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' \
  > ~/.config/corporate-ca/turktelekom-ca-bundle.pem
```
`watch-errors.sh` bu dosya varsa otomatik olarak `NODE_EXTRA_CA_CERTS` olarak
kullanır (bkz. `OPENCODE_CA_BUNDLE` ortam değişkeni) — ekstra bir ayar
gerekmez. **Doğrulanmış etki**: opencode yanıt süresi 90s+ (timeout/fallback)
→ ~9s'ye düştü.

### 6) Ön kontroller
- Uygulamanın `application.properties`'teki portu boş olmalı (`ss -ltnp | grep <port>`).
- `opencode models` litellm modellerini listelemeli.
- `claude --version` çalışmalı (fallback için).
- `ssh -T git@github.com` → "successfully authenticated" dönmeli.
- `GITHUB_REPO` ve `GITHUB_TOKEN` set edilmiş olmalı.

## Demo çalıştırma

**Terminal 1:**
```bash
mvn spring-boot:run
```

**Terminal 2:**
```bash
export GITHUB_REPO=OnurCemER/ai-error-demo
export GITHUB_TOKEN=...
./watch-errors.sh
```

**Tarayıcı:** `http://localhost:8080` (ya da `application.properties`'te ayarladığınız port)

1. "NullPointerException Firlat" butonuna basın.
2. Sayfada hata fragment'i görünür.
3. Terminal 2'de sırasıyla: yakalanan hata bloğu → GitHub issue oluşturma →
   `bugfix/*` branch açma → opencode/claude çağrısı → `mvn compile` →
   conventional-commit → GitHub'a push (SSH) → PR oluşturma → özet (issue+PR linki).
4. Terminal 1'de DevTools restart log satırları görünür.
5. Aynı butona tekrar basın — artık hata almadan çalışır.
6. GitHub'da açılan issue'yu ve PR'ı gerçek arayüzde kontrol edin.

**Önemli — sırayla test edin:** her yeni hata `origin/prod`'un en güncel
halinden taze bir branch açtığı için, **birinci hatayı tam döngüsüyle
(fix → restart → buton çalışıyor) bitirmeden ikinci hatayı tetiklemeyin** —
aksi halde ikinci hata için yapılan checkout, birinci hatanın henüz
commit/push edilmemiş yerel düzeltmesini çalışma ağacında geri alır (düzeltme
kendi branch'inde güvende kalır, ama yerel demo anlık olarak "bozulmuş" görünür).

## Demo sonrası sıfırlama — iki türü var

**Prova reset'i** (rehearsal sırasında, gerçek GitHub'a dokunmadan):
```bash
git checkout prod -- src/main/java
git checkout prod
: > logs/error.log
```
`.watch-tmp/` (dedup state) buna dahil değil — bu sayede aynı hatayı tekrar
tetiklediğinizde gerçek repoda mükerrer issue/PR AÇILMAZ, mevcutlar yeniden
kullanılır.

**Tam reset** (sadece canlı demodan hemen önce, bilerek — bir sonraki
tetiklemede gerçek yeni issue + PR açılacağını bilerek yapın):
```bash
git checkout prod -- src/main/java
git checkout prod
: > logs/error.log
rm -rf .watch-tmp
```

## Notlar / dikkat edilecekler

- **Gerçek repo kirlenmesi riski**: dedup mekanizması (`.watch-tmp/incident-map.json`)
  aynı hatanın tekrar tetiklenmesini "zaten işlendi" sayıp mevcut issue/branch/PR'ı
  yeniden kullanır. Bu dosyayı silmek (tam reset) her seferinde gerçek yeni
  kayıtlar açar — provalarda sadece "prova reset'i" kullanın.
- **SSH port 22 bu ağda filtreleniyor**: `ssh -T git@github.com` doğrudan
  port 22 üzerinden "Connection timed out during banner exchange" veriyor
  (TCP bağlantısı açık görünse de SSH trafiği filtreleniyor). GitHub'ın
  resmi `ssh.github.com:443` alternatifi çalışıyor, `~/.ssh/config`'teki
  ayar bunu otomatik kullanıyor — farklı bir ağda çalıştırırken bu ayara
  gerek olmayabilir ama zararı yok.
- **opencode yavaşlığı/timeout'ları çözüldü**: kök neden litellm hub'ının
  kurumsal, kendinden imzalı sertifikasıydı (bkz. yukarıdaki "TLS — litellm
  hub" kurulum adımı) — Node.js'in bunu reddetmesi dakikalarca süren gizli
  tekrar denemelere yol açıyordu. `OPENCODE_CA_BUNDLE` dosyası mevcutsa
  script otomatik düzeltiyor (doğrulanan etki: 90s+ → ~9s). 90 saniyelik
  `OPENCODE_TIMEOUT` yine de bir güvenlik sınırı olarak duruyor; süre
  aşılırsa otomatik `claude` fallback'ine geçilir. Sertifika kurulumu
  yapılmadıysa `SKIP_OPENCODE=1` ile doğrudan `claude`'a geçebilirsiniz.
- **WSL ↔ Windows log izleme sorunu çözüldü**: uygulama Windows'ta (örn.
  IntelliJ debug) çalışırken `tail -F`, WSL'e inotify olayları ulaşmadığı
  için `logs/error.log`'daki yeni satırları hiç yakalamıyordu (bu coreutils
  derlemesinde `--disable-inotify` de yok). `watch-errors.sh` artık
  `poll_tail()` adlı, `stat()` tabanlı basit bir polling fonksiyonu
  kullanıyor — hem WSL hem Windows tarafından yazılan log dosyalarında
  güvenilir çalışır.
- `index.html`/`app.js` AI tarafından değiştirilmez; tarayıcıda eski önbellek
  görürseniz sert yenileme yapın (Ctrl+Shift+R).
- DevTools sadece derlenmiş `target/classes`'ı izler, `src/main/java`'yı değil
  — bu yüzden `watch-errors.sh` her AI düzeltmesinden sonra `mvn compile`
  çalıştırır. Bu adım atlanırsa otomatik restart hiç tetiklenmez.
- `opencode run`'a `--dir` bayrağı bu WSL ortamında path hatası verdiği için
  script bunun yerine proje dizinine `cd` ediyor.
- **Signature kayması**: dedup imzası stack trace'teki dosya/satır bilgisine
  dayanıyor; buggy dosyalar elle düzenlenirse (satır kayarsa) aynı hata "yeni"
  sayılabilir. İki sabit bug'lık bu demo için önemli değil.
- Kimlik bilgileri (`GITHUB_TOKEN`, SSH private key) hiçbir zaman terminale
  yazdırılmaz, `.git/config`'e veya state dosyasına kaydedilmez. SSH deploy
  key parolasızdır ama sadece bu repoya yazma erişimi olduğu için blast
  radius sınırlıdır.
