# ADR-0046 — Uygulama takım adresine geçer: davet bağlantısının sunucusu, oturumu koruyan adres değişimi

- **Status:** Accepted
- **Date:** 2026-10-07
- **Related task:** OPH-356 (uzantıda EE-300, uzantının ADR-0021'i); 2026-10-07 UI denetimi #5, #7

## Context

Uzantı takımı yalnız `Host`'tan çözer (`<slug>.<baseDomain>`); varsayılan adres
(`api.alliswell.space`) takım uçlarına 404 der. Uzantının ADR-0021'i davet bağlantısına sunucuyu
koyar (`…/#/join/<token>?server=<takım origin'i>`) ve apex'te kişinin takımını söyleyen
`GET /ee/me/team`'i ekler. Uygulamanın iki şeye karar vermesi gerekiyordu: bir bağlantıdaki
`server`'a ne zaman güveneceği (yoksa bu bir yönlendirme/kimlik avı açığıdır) ve takım adresine
geçerken oturumun ne olacağı (sunucu sayfası adres değişince çıkış yapar).

## Decision

1. **`server` yalnız https, yalnız origin, yalnız güvenilen apex'e tek etiketle bağlı, rezerve
   olmayan bir host** olduğunda kabul edilir (`acceptJoinServer`, `teamOriginOf`'un kuralı) ve
   davetin kendisi de o takımı (`teamSlug`) söylemelidir. Host, hiçbir şey gönderilmeden ekranda
   gösterilir. Geçersizse "bu bağlantı bu uygulamaya ait değil" — sessiz yok sayma yok.
2. **Güvenilen apex:** oturum açıksa yalnız sunucunun `/ee/status` → `baseDomain`'i. Oturum
   kapalıysa `/ee/status` okunamaz (oturum ister); güven, uygulamanın zaten konuştuğu sunucuya
   bağlanır: o host ve üst alanı (`api.example.com` → `example.com`). Bağlantı uygulamayı yalnız
   zaten konuştuğu sunucunun bir kardeşine götürebilir. (ADR-0021 §4 "varsayılan sunucunun
   baseDomain'i" der; oturumsuz yarı bu ADR'nin kararıdır.)
3. **Takım adresine geçiş oturumu korur** (`switchToTeamOrigin`): takım host'u başka bir sunucu
   değil, aynı kurulumun alt alanıdır — yalnız 1. ve `/ee/me/team`'in ürettiği adreslerle çağrılır.
   Geçiş Ana sayfadan yapılır (önce Ana sayfaya gidilir, sayfa geçişi bitince adres değişir).
4. **`/join/:token` her durumda açılır** — oturum kapalıyken de, oturum geri yüklenirken de; davet
   ekranı oturumu kendisi bekler. Hesabı olan adres takımın sunucusunda girer, bağlantı (sorgusuyla)
   girişten sonra yeniden açılır.

## Alternatives considered

- **`/ee/status`'u oturumsuz açmak** (yalnız `baseDomain`) — core API'nin kasıtlı kararı (lisans
  bilgisi operatörün işi) değişirdi; oturumsuz yarı için uygulamanın zaten seçtiği sunucu yeterli
  bir güven çapası.
- **Geçişte çıkış yapıp yeniden girmek** — davet edilen ve apex'te giren üye parolasını yeniden
  yazardı; aynı kurulumda token geçerli olduğundan gereksiz.
- **Geçişi olduğu ekranda yapmak** — örtülü (duraklatılmış) sağlayıcılar adres değişince bir sonraki
  build'in içinde yeniden kurulur; Flutter bunu reddeder (LESSONS `flutter-app`).

## Consequences

- Bir bağlantı uygulamanın sunucusunu değiştirebilir; kural 1–2 bunu kardeş host'larla sınırlar ve
  `join_screen_test`, `team_origin_test` yabancı/http/yollu/rezerve host'u adıyla dener.
- Kendi sunucusunu kuran ve `baseDomain`'i API host'unun üst alanı olmayan kurulumda oturumsuz
  açılan davet bağlantısı "ait değil" der; oturum açıkken `baseDomain` doğru cevabı verir.
