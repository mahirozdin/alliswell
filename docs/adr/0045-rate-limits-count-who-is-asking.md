# ADR-0045 — Hız sınırı kimin sorduğunu sayar: kimlikli istek kullanıcıya, kimlik bilgisi uçları IP + hesaba

- **Status:** Accepted
- **Date:** 2026-10-07
- **Related task:** OPH-357; 2026-10-07 UI denetimi #24, #25, D3

## Context

`@fastify/rate-limit` her isteği `request.ip` ile sayıyordu (API anahtarları hariç, ADR-0032 §5).
Bir fabrikada herkes tek NAT adresinin arkasındadır: vardiya başında 12 kişi giriş yapınca 10/dk
giriş sınırı hepsine birden yetiyordu ve dokuz birimli bir üyenin senkron döngüsü, 300/dk genel
bütçeyi bütün iş arkadaşlarıyla paylaşıyordu. Denetimde girişlerin yaklaşık üçte biri ilk
denemede 429'a düştü. 429 gövdesinde `code` da yoktu; istemci bunu İngilizce "Unexpected server
response" diye gösterdi.

Kısıt: kaba kuvvet koruması zayıflamamalı. Tek hesabın 12 yanlış parolası yine 429 almalı; tek
adresten çok hesap denemek (password spraying) sınırsız kalmamalı. Limiter kimlik doğrulamadan
önce (`onRequest`) çalışır; `request.user` henüz yoktur.

## Decision

1. **Kova = kim soruyor.** Genel `keyGenerator` (`src/lib/rate-limit.js`, `identityRateKey`):
   API anahtarı → kendi kovası (değişmedi); geçerli erişim token'ı → `user:<sub>`; diğer her şey →
   `ip:<ip>`. Token'ın imzası, issuer/audience'ı ve süresi limiter'ın içinde `app.jwt.verify` ile
   doğrulanır: sahte ya da süresi dolmuş bir token yeni kova açamaz, IP'ye düşer. Sınır
   `RATE_LIMIT_MAX` (varsayılan 300/dk) — artık kullanıcı başına.
2. **Kimlik bilgisi uçları** (register, login, refresh, logout, OAuth girişi) için iki katman:
   - hesap kovası: IP + gövdenin adlandırdığı hesabın SHA-256 özeti (e-posta küçük harfe
     indirilir; refresh/OAuth'ta token), `preValidation`'da (gövde ayrıştırılmış olmalı),
     `RATE_LIMIT_AUTH_MAX` (varsayılan 10/dk). Tek hesabın yanlış parolaları burada durur.
   - IP tavanı: bu uçların hepsinde ortak tek kova, `RATE_LIMIT_AUTH_IP_MAX` (varsayılan
     10 × `RATE_LIMIT_AUTH_MAX` = 100/dk). Tek adresten çok hesap denemek sınırlı kalır; aynı
     NAT'tan bir vardiyanın girişi sığar.
   Oturum açık uçlar (MFA, parola değişimi, oturumlar) `RATE_LIMIT_AUTH_MAX`'ı kullanıcı başına
   sayar — TOTP tahmini kişi başına sınırlıdır, adres değiştirmek yardım etmez.
3. **429 gövdesi kodludur:** `{ statusCode: 429, code: 'RATE_LIMITED', error, message, retryAfter }`
   (`retryAfter` saniye) + `Retry-After` başlığı. Bütün limiter'lar (uzantınınkiler dahil) aynı
   `errorResponseBuilder`'ı miras alır; kendi `setErrorHandler`'ı olan bir bağlam (uzantının HTML
   portalı) kendi 429'unu çizer.

## Alternatives considered

- **Yalnız IP sınırını yükseltmek.** NAT'ı rahatlatır ama tek kullanıcıya kaba kuvvet bütçesini de
  büyütür; kaba kuvvet koruması ile ofis kullanımı aynı sayıya bağlı kalır.
- **Kimliği kimlik doğrulamadan sonra okumak (`preHandler`).** Doğrulanmamış istekler limiter'dan
  önce DB/argon2 maliyetini öder; ayrıca `authenticate` 401 verdiğinde hiç sayılmaz.
- **Senkron uçlarına ayrı bir kova.** D3 ölçümü gereksiz gösterdi: dokuz birimli üyenin ilk girişi
  27 pull (birim başına 3 sayfa), sıradan açılış 9, kararlı döngü ~2,6 istek/dk (ekrandaki birim
  60 sn'de, diğer sekizi 300 sn'de bir) — kullanıcı başına 300/dk'nın onda biri. Döngüyü toplamaya
  da gerek yok (`apps/app/test/sync/sync_request_budget_test.dart` ölçer).

## Consequences

- Aynı adresteki insanlar birbirinin bütçesini tüketmez; bir kişinin çok cihazı ise aynı bütçeyi
  paylaşır (300/dk bunu karşılar).
- Her kimlikli istekte bir JWT doğrulaması fazladan çalışır (HMAC; ihmal edilebilir).
- `authenticate` route'un kendi `onRequest`'inde limiter'dan önce çalıştığı için geçersiz
  token'lı 401'ler o route'larda sayılmaz — bu davranış ADR'den önce de böyleydi.
- `RATE_LIMIT_AUTH_IP_MAX` yeni bir ortam değişkenidir (SELF-HOSTING §3, `.env.example`).
