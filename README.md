# ai-error-demo

Yapay zeka otomasyonu demosu: bir Spring Boot uygulamasında fırlatılan hatayı,
ayrı bir izleyici script yakalayıp **opencode** (litellm modelleri üzerinden,
fallback: **Claude Code CLI**) ile otomatik olarak analiz ettirir ve kaynak
kodu düzeltir. Spring Boot DevTools sayesinde düzeltme sonrası uygulama
otomatik yeniden başlar.

## Ön kurulum (bir kere)

```bash
cd ai-error-demo
git init
git add -A
git commit -m "Initial buggy baseline for AI-fix demo"
chmod +x watch-errors.sh
```

Kontrol edilecekler:
- Port 8080 boş olmalı (`ss -ltnp | grep 8080`).
- `opencode models` litellm modellerini listelemeli.
- `claude --version` çalışmalı (fallback için).

## Demo çalıştırma

**Terminal 1:**
```bash
mvn spring-boot:run
```

**Terminal 2:**
```bash
./watch-errors.sh
# Modeli degistirmek icin: AI_MODEL=litellm/deepseek-ai/DeepSeek-V4-Flash ./watch-errors.sh
# opencode'un vazgecme suresini degistirmek icin (varsayilan 90s): OPENCODE_TIMEOUT=60 ./watch-errors.sh
# opencode'u tamamen atlayip dogrudan claude kullanmak icin: SKIP_OPENCODE=1 ./watch-errors.sh
```

**Tarayıcı:** `http://localhost:8080`

1. "NullPointerException Firlat" butonuna basın.
2. Sayfada hata fragment'i görünür.
3. Terminal 2'de: yakalanan hata bloğu → opencode çağrısı ve çıktısı akışı →
   `mvn compile` → "Devtools restart'i bekleniyor..." mesajı.
4. Terminal 1'de DevTools restart log satırları görünür
   (`Restarting due to 1 class path change`, `Started AiErrorDemoApplication...`).
5. Aynı butona tekrar basın — artık hata almadan çalışır.
6. "Warning Firlat" butonu için aynı döngüyü tekrarlayın.

## Demo sonrası sıfırlama

```bash
git checkout -- src/main/java
: > logs/error.log
rm -rf .watch-tmp
```

## Notlar / dikkat edilecekler

- **Test edildi ve uçtan uca çalışıyor**: NPE hatası için `claude` fallback
  ~1 dakikada doğru düzeltmeyi uyguladı; `BusinessWarningException` hatası
  için `opencode` (model: `litellm/moonshotai/Kimi-K2.7-Code`) doğru
  düzeltmeyi uyguladı ama **~11 dakika sürdü** — bazı ücretsiz litellm
  modelleri çok yavaş/tutarsız olabiliyor. Bu yüzden script'e 90 saniyelik
  bir `timeout` eklendi (`OPENCODE_TIMEOUT` ile ayarlanabilir); süre aşılırsa
  otomatik olarak `claude` fallback'ine geçilir. **Canlı demodan önce**
  kullanacağınız modeli bir kere elle deneyip (`opencode run "test" --model
  ... --agent build --format default`) gerçek yanıt süresini ölçmeniz
  önerilir; yavaşsa `SKIP_OPENCODE=1` ile doğrudan `claude`'a geçebilirsiniz.
- AI çağrısı (claude ile) tipik olarak 30-90 saniye sürüyor; canlı demoda bu
  süre için konuşma hazırlayın ("AI stack trace'i analiz ederken...").
- `index.html`/`app.js` AI tarafından değiştirilmez; tarayıcıda eski önbellek
  görürseniz sert yenileme yapın (Ctrl+Shift+R).
- DevTools sadece derlenmiş `target/classes`'ı izler, `src/main/java`'yı değil
  — bu yüzden `watch-errors.sh` her AI düzeltmesinden sonra `mvn compile`
  çalıştırır. Bu adım atlanırsa otomatik restart hiç tetiklenmez.
- `opencode run`'a `--dir` bayrağı bu WSL ortamında path hatası verdiği için
  script bunun yerine proje dizinine `cd` ediyor.
