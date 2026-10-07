# TASKS — AllisWell backlog

> **How to use:** this file holds **open work only**, in order — the first task below without ⏸️
> is the **next task**. Don't read the file whole to find it: `npm run next` prints it with its
> epic's intro (`-- --batch 4` for a loop turn, `-- --summary` for the counts). The pointer also
> lives in [STATE.md](STATE.md), and `check:docs` keeps the two equal. Rules and workflow:
> [../AGENTS.md](../AGENTS.md). Spec: [BLUEPRINT.md](BLUEPRINT.md). Traps and decisions by area:
> [LESSONS.md](LESSONS.md) (grep the area, don't read it whole).
>
> **Format** (read by `scripts/tasks/tasks.mjs`): `## Epic NN — …` sections, `### OPH-NNN — …`
> tasks, `- [ ]` boxes. **⏸️ in a task heading** = it waits on the owner (an account, a console, a
> store review): it is never picked, STATE must name it, and removing the ⏸️ puts it back in the
> queue. Order is dependency — a task that needs a parked one is parked too.
>
> **A closed task is deleted, not ticked** — its record is git history and the CHANGELOG, and
> `npm run check:docs` fails on a closed task left behind. Before deleting it: a trap that can
> silently recur → LESSONS.md; an owner decision → STATE.md. Every task up to Epic 33
> (OPH-001…OPH-350), with its full notes, is in `git show 85b6c1b:docs/TASKS.md`.

---

## Sahibin adımını bekleyen işler — ajan için kod işi yok

Kod tarafları kapalı; kalan kutular sahibin hesap/panel adımları (STATE → "Kullanıcıdan bekleyen").

### OPH-142 — Critical-alerts entitlement application (user action; code is ready) ⏸️ SAHİP

_(2026-07-24'te başvuru "gönderiliyor" diye kayıtlı; sonucu kayıtlı değil — gönderildiyse ilk
kutuyu işaretle.)_

- [ ] **Mahir (Account Holder):** submit
      <https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/> —
      justification draft in NOTIFICATIONS.md §2. Expect refusal for a task manager; AlarmKit
      (OPH-141) is the primary path — this is belt-and-braces for muted phones on iOS < 26.
- [ ] If granted: add `com.apple.developer.usernotifications.critical-alerts` = true to
      `Runner.entitlements`, regenerate provisioning profiles. **No code change** — OPH-139
      already gates on the runtime grant, and the second "Critical Alerts" permission prompt +
      Settings toggle appear automatically.

---

## Epic 34 — 2026-10-07 UI denetimi: oturum verisi, takım adresi, hata katmanı, ekranlar

_Kaynak: 2026-10-07 canlı UI denetimi (v1.15.0; rapor sahibin makinesinde,
`~/Documents/alliswell-ee-ui-audit-2026-10-07.md`). Ana tabloda 89 bulgu (#1–#89) + 4
doğrulanacak (D1–D4). Bu epic uygulamanın (`apps/app`, uzantı ekranları dahil) ve core API'nin
(`apps/api`) payıdır; sunucu modülleri uzantı deposunun karşı işlerindedir (EE-299…EE-304) ve
**istemcinin uyacağı sözleşme o işlerin "Sözleşme" satırındadır** — core belgelerine uzantının
tasarımı yazılmaz. Satır numaraları rapordandır ve kayar; her iş kendi metnini yeniden ölçer._

**İkiz yok:** hiçbir çift core şemasını, replikayı ya da dikişi değiştirmiyor. Her iş tek başına
kapanır ve sunucunun **hem eski hem yeni** davranışına dayanıklıdır: yeni alan yoksa bugünkü
davranış, yeni uç 404 ise "ipucu yok", bilinmeyen durum değeri nötr çizilir.

**Sıra:** OPH-356 (P0, #5 + takım adresi) → OPH-357 (core API + hata katmanı) →
OPH-358 (talep/onay ekranları) → OPH-359 (kabuk, gezinme, erişilebilirlik) → OPH-360 (yönetim ve
rapor ekranları). **Kritik yol:** OPH-357 (auth — hız sınırı giriş yolunu değiştirir: `auth.test.js`,
`auth-refresh.test.js`, `auth-me.test.js`).

**Her işin sabit DoD'si:** i18n tr+en (`check:i18n`), DESIGN tokenları, açık ve koyu tema, dokunma
hedefi ≥ 44 px; test adları `UI-AUDIT #n:` önekli; core API değişikliği docs/API.md'de (MCP yüzeyi
değişmiyor — rule 12 gerekçesi: bu epicin core API değişiklikleri hata gövdesi ve hız sınırıdır,
araç değil). Cihazda bakılacaklar (ekran okuyucu, telefon yerleşimi) DEVICE-CHECKS.md'ye.

**Risk planı (rule 10):** OPH-357 hız sınırının anahtarını değiştirdi — güvenlik kararı ADR-0045'te.

---

### OPH-358 — Talep, onay, bilgi bankası ve ekipman ekranları

**Bulgular:** #6 (istemci), #9 (istemci), #14 (istemci etiketi), #21, #28 (istemci), #31, #33, #34,
#36, #37 (istemci), #38 (istemci), #48 (istemci), #71, #72, #73, #74, #75, #77 (istemci), #78
(istemci), #82. **Karşı yarı:** EE-302, EE-304 (sözleşmeler orada).

- [ ] **#6** `features/ee/ui/ticket_detail_screen.dart` ~118 + `history_tab.dart`: Geçmiş sekmesi
      hata durumunda Tekrar dene; satırlar kim/ne zaman ve form düzeltmesini okunur çizer.
- [ ] **#9** `new_ticket_screen.dart` ~318/383 + `new_ticket_providers.dart` ~57: taslak kutusu yoksa
      çevrimdışı form taslak sözü vermez ("bağlantı gelince gönderin" durumu); kutu varsa bugünkü akış.
- [ ] **#21** `_CommentCard` (~1016): yazar adı (sunucunun yorum meta'sı; yoksa üye listesinden
      `authorId`), taraf ve kanal rozeti (e-posta/portal), taraf hizası; talep sahibi kendi
      talebindeyse composer "Masaya yaz", e-posta kaynaklı talepte "e-postayla gönderilir" ipucu.
- [ ] **#28** `notifications_providers.dart` ~99: durum anahtarı `ee.tickets.status.<v>` ile çevrilir
      (yeni alan yoksa eski parametre anahtar sayılır; bilinmeyen değer ham değil nötr metin).
- [ ] **#31** `new_ticket_screen.dart` ~331/237: `canPop` değilse yeni talebe ya da
      `/settings/team/my-tickets`'e gider + snackbar ("Bu çözdü" dalı dahil).
- [ ] **#33** `_Relations` (~327) + `data/ticket_links_api.dart`: ilişkili/kopyası/alt talep listesi,
      bağla/kopar (izinle), "tekrar açıldı" yeni talebi açar.
- [ ] **#34** yeni talep formu ve `ticket_composer.dart`: dosya seçici; talep oluşunca core'un yükleme
      yürüyüşüyle `ticket` hedefine, yanıt/iç not gönderilince `ticket_comment` hedefine (iç notun
      dosyası masanın kalır — sunucu zaten süzüyor). Talep sahibi birimin üyesi değilse seçici
      gizli + yazılı sınır (core yükleme yürüyüşü üyelik ister; uzantının parking lot'unda satır).
- [ ] **#36** `kb_editor_sheet.dart` ~86: servis seçici; servissiz makalede "kimseye önerilmez" notu.
- [ ] **#37** `asset_detail_screen.dart`: "Değişiklikler" bölümü (uç yoksa bölüm çizilmez).
- [ ] **#38** KB makalesinde masaya önlenen talep sayaçları; onay detayında ekler/yazışma (veri gelince).
- [ ] **#48** talep detayı: "Firma: … — firma portalında görünür" satırı + bağla/kaldır seçici
      (izinle); alan yoksa satır yok.
- [ ] **#14 (etiket)** onay ekranları `withdrawn` durumunu "Geri çekildi" çizer; bilinmeyen durum nötr.
- [ ] **#71** `ticket_worklog_section.dart`: yerel tarih, "45 dk"/"1 sa 15 dk", 0 için "En az 1
      dakika", görünür sil (⋮).
- [ ] **#72** `ticket_bulk.dart` ~55 + i18n: `TICKET_INVALID_TRANSITION` için toplu işleme özgü metin.
- [ ] **#73** `ticket_detail_screen.dart` ~204: iptalde "… tarihinde iptal edildi".
- [ ] **#74** `approval_detail_screen.dart` ~464: "Talebi aç"tan dönünce `ref.invalidate`.
- [ ] **#75** `kb_article_screen.dart` ~182: "Emekliye ayır" onay diyaloğu.
- [ ] **#77** değişiklik/onay ekranı: pencere geçmişken "Pencere geçti" rozeti (`windowEnd < now`).
- [ ] **#78** ekipman kartında `NumberFormat`/`DateFormat` (para, tarih), açık süre etiketi.
- [ ] **#82** seçilen servis kartı `serviceIcon(service.icon)`.
- [ ] Testler: `ticket_detail` testleri + `ticket_composer_test.dart` (#21, #34, #48), `history_tab_test.dart`
      (#6), `new_ticket_screen_test.dart` (#9, #31, #82), yeni `ticket_relations_test.dart` (#33),
      `ticket_attachments_test.dart` (#34), `kb_screens_test.dart` (#36, #38, #75),
      `asset_screens_test.dart` (#37, #78), `approval_detail_test.dart` (#14, #74),
      `change_screens_test.dart` (#77), `ticket_worklogs_test.dart` (#71), `ticket_bulk_test.dart` (#72),
      `notifications_test.dart` (#28); golden'lar açık/koyu güncel.

**Kabul:** raporun TLC/ONY senaryoları: #218'de her balonda yazar ve taraf; #209'un "tekrar açıldı"
bağı iki detayda da görünür; doğrudan URL'den gönderilen talep boş sayfada kalmaz.

### OPH-359 — Kabuk, gezinme ve erişilebilirlik; genel Türkçe metinler; toplantı ve AI düğmesi

**Bulgular:** #10, #11, #12, #29, #30, #32, #54 (istemci), #55, #57, #58, #59, #60, #63, #64
(portal ekranı dışı). **Karşı yarı:** EE-303 (#54 `failureCode`, #63 toplantı 404 kodu).

- [ ] **#10** `screens/home_shell.dart` ~367 `extendBody` + `ticket_queue_screen.dart` ~61: iç
      Scaffold FAB'ları nav yüksekliği kadar yukarıda; diğer iç FAB'lar taranır.
- [ ] **#11** `workspaces/ui/workspace_switcher.dart` ~89: `isScrollControlled`, `useRootNavigator`,
      kaydırılabilir liste.
- [ ] **#12** rail semantiği (`home_shell.dart` ~283–360, `approvals_entry.dart` ~107): önce
      Semantics debugger ile kök neden ölçülür (GlassSurface/BackdropFilter, scrollable+extended);
      düzeltme + Tab sırası testi; ekran okuyucuyla doğrulama DEVICE-CHECKS'e.
- [ ] **#29** uzantı liste ekranları (`#/tickets`, `#/kb`, `#/changes`, `#/problems`, `#/meetings`):
      AppBar'da birim adı + seçici; seçili alan birim değilse "Bir birim seçin" durumu; KB boş
      durumu yazma önerisini izne bağlar (`kb_providers.dart` ~58, `sections.dart` ~59).
- [ ] **#30** ortak `AwAppBar` yardımcısı: `canPop` ise geri, değilse Ana sayfa (Onaylar'daki
      yedek `approvals_screen.dart` ~58 buraya taşınır); 37 rota.
- [ ] **#32** doğrudan açılan `#/tickets/:id`: `syncEnginesProvider` kökte izlenir ya da tek
      seferlik pull + sunucudan okuma yedeği (`home_shell.dart` ~172, `ticket_archive_screen.dart` ~116).
- [ ] **#54** `meeting_screen.dart` ~266 / `meetings_screen.dart`: `failureCode` çevirisi + "AI
      anahtarları" eylemi; "Kayıt yükle" akışı (mevcut yükleme ucuna).
- [ ] **#55** `features/ai/ui/ai_fab.dart` ~84: `onPressed` balonu açar, çift tetikleme bayrağı.
- [ ] **#57** `quick_access/ui/quick_access_bubble.dart` ~110: varsayılan konum alt bölge, kaydırmada
      solar (rozet varken de); Onaylar rail satırı rail dolgusuyla hizalı.
- [ ] **#58** 390 px: eylemler ⋮'ye, nav `labelBehavior`, liste alt dolgusu FAB'ları hesaba katar.
- [ ] **#59** `router.dart` ~733: `optionURLReflectsImperativeAPIs` ya da yol rotalarına `context.push`;
      talep/onay/KB kendi adresini taşır.
- [ ] **#60** `home/month_calendar.dart` ~28/192: `DateFormat(locale)`; semantik etiketler i18n;
      tr.json ~1507, ~1091–1129 ("Task geçmişi", "Inbox").
- [ ] **#63** `team_mail_screen.dart` ~208 alan etiketleri, webhook olay adları `ee.webhooks.event.<id>`,
      tr.json "workspace" → "çalışma alanı", toplantı 404 metni koddan.
- [ ] **#64** (portal dışı) kuyruk checkbox'ı, arşiv araması, `AwSlaCountdown`, `approval_reason_dialog.dart`
      `semanticLabel`/`labelText`, `ColorSwatchDot` renk adı.
- [ ] Testler: yeni `test/features/shell/fab_inset_test.dart` (#10, #58), `workspace_switcher_test.dart`
      (#11), yeni `test/features/shell/rail_semantics_test.dart` (#12, #57), yeni
      `test/features/ee/unit_scope_test.dart` (#29), `ticket_route_test.dart` (#30, #32, #59),
      `meeting_screen_test.dart` (#54), yeni `test/features/ai/ai_fab_test.dart` (#55),
      `test/features/home` takvim testi (#60), `team_mail_test.dart`, `team_webhooks_test.dart` (#63).

**Kabul:** telefonda kuyruk FAB'ı görünür ve doğru açılır; 10 birimin hepsi seçilebilir; 1440 px'te
Tab rail'e girer ve "Talepler" okunur; derin bağlantıda geri/Ana sayfa düğmesi var.

### OPH-360 — Yönetim, portal bağlantıları ve rapor ekranları

**Bulgular:** #13 (istemci), #18 (istemci), #22 (istemci), #23, #44 (istemci), #45, #46 (istemci —
SLA hedef tablosu), #47, #52, #53, #56 (istemci), #64 (portal ekranı), #65, #67, #68, #79, #80, #88,
#89 (ekran adı), D2. **Karşı yarı:** EE-300 (#18), EE-301 (#13, #67), EE-303 (#22, #47, #52, #53, #56).

- [ ] **#13, #68, #67, #65, #64, D2** `portal_links_screen.dart`: "Uzat" süre seçimi (1/2/7/30 gün,
      `ee.portal.ttlDays`) ve onay; satırda oluşturma tarihi, birim, servis adları (alan yoksa bugünkü
      satır); iptal diyaloğu "Vazgeç" / "Bağlantıyı iptal et" (hata rengi); diyalog adları ve etiketler;
      `Clipboard.setData` try/catch + hata snackbar'ı (~557).
- [ ] **#18** yeni `/settings/team/customers` ekranı (firmalar → kişiler, ekle/davet/kapat/aç,
      firmayı yeniden adlandır/arşivle; izinle). Rota uzantının el kitabı kapısına girer: uzantıda
      GUIDE-ADMIN satırı gerekir (EE-304 ekran indiyse yazar; bu iş önce inerse uzantıya tek satırlık
      belge commit'i bırakılır).
- [ ] **#22, #23, #46** `sla_admin_screen.dart`: silmeden önce etkiyi anlatan onay (rol/webhook
      kalıbı; `team_units_screen.dart` ~173 ve `team_invites_screen.dart` ~247 aynı); varsayılan
      silmenin 409'u okunur metin; ad alanı `onChanged` → Kaydet etkin (#23); politikada hedef
      tablosu (`sla_admin_providers.dart` ~57 `saveTarget`); talep detayı SLA çipi süre yoksa ihlal
      zamanı.
- [ ] **#52, #53, #88** `sla_dashboard_screen.dart`: Aşıldı/Yaklaşıyor/Tutuldu kartı, payda
      "N değerlendirilen" (alan yoksa istemci toplar), "varsayılan politika yok" uyarısı, ihlal satırı
      #numara ile talebe gider; `NumberFormat` ("%40,3") ve süre yardımcısı ("3 g 21 sa") — perf
      ekranında da (`performance_screen.dart` ~228).
- [ ] **#56** kuyruk ⋮ ve denetim ekranında "CSV indir" (`tickets.export` / denetim izniyle).
- [ ] **#44, #89** `audit_log_screen.dart` ~58/260: tür adları `ee.audit.entity.<type>`, satırda kayıt
      adı/numarası ve bağlantı, ekran başlığı "Denetim günlüğü" (Ayarlar satırıyla aynı).
- [ ] **#45** `team_roles_screen.dart` ~288: `ee.perm.<id>.description` (71 izin, tr+en; anahtar
      yoksa sunucu metni).
- [ ] **#47** `absences_screen.dart` ~278: liste `to` = bugün+365 (seçiciyle aynı ufuk).
- [ ] **#79** `form_designer_screen.dart` ~253: `version==0` iken yalnız "Henüz yayınlanmadı".
- [ ] **#80** `team_units_screen.dart` ~236: boş üye listesinde `AwEmptyState`.
- [ ] Testler: `portal_links_test.dart` (#13, #65, #67, #68, D2), yeni `customers_screen_test.dart` (#18),
      `sla_admin_test.dart` (#22, #23, #46), `sla_dashboard_test.dart` (#52, #53, #88),
      `performance_screen_test.dart` (#88), `audit_log_test.dart` (#44, #89, #56), `team_roles_test.dart`
      (#45), `absences_test.dart` (#47), `form_designer_test.dart` (#79), `units_test.dart` (#80);
      golden'lar açık/koyu güncel.

**Kabul:** 720 saatlik link uzatılınca bitişi geri gelmez; firma kişisi uygulamadan kapatılabilir;
SLA panosu ihlal sayısını ve "191 değerlendirilen"i gösterir; izin açıklamaları Türkçe.

---

## Backlog / v2 parking lot

Yapılmamış ve bir işe bağlanmamış her şey. Bir madde bir epic'e alınınca buradan silinir.

- Workspace sharing & roles UI (multi-user workspaces are schema-ready).
- Project documents (block editor) — Phase 5 detail tasks to be expanded when reached.
- Timeline view; smart lists/filters DSL; global single-screen search (per-screen search
  shipped in Epic 15; kanban shipped in Epic 15 — OPH-168).
- Search v2: FTS5 external-content upgrade (bm25 ranking — ADR-0013 upgrade path),
  server-side fold columns for a first-class API `?q=` (the server's FULLTEXT still folds `I`
  but not `ı` — OPH-167), file-name search in Dosyalar (OPH-170).
- Task description v2: OG link previews (needs a server-side unfurl proxy — OPH-164, OPH-201),
  rich formatting.
- Tag management v2: merge tags, usage counts, tag colors in board/list filters.
- Files v2: desktop drag-to-move into folders (target-picker sheet is v1), bulk move/delete.
- Attachments v2: multipart >5 GB uploads, thumbnails/transcodes, storage quota in the plain
  build (today only the per-file `maxUploadBytes` ceiling), local binary cache for offline
  viewing, inline video playback, public share links (v1 shipped in Epic 14 — ATTACHMENTS.md §11).
- **Round 9 park kuyruğu:** sunucu tarafı zil sesi dönüştürme (ffmpeg → ≤30 sn caf, mp3
  yüklemelerini iOS bildiriminde kullanılabilir kılar — OPH-181 bilinçli olarak
  doğrulama+dürüst mesajla yetiniyor); **watchOS companion hedefi** (özel long-look +
  `WKInterfaceDevice` haptikleri + complication — kararı OPH-183 veriyor); cihazlar arası
  **sunucu tarafı ayar deposu** (hatırlatıcı profili + tarih biçimi + ses seçimi bugün
  cihaz-yerel, `notification_privacy` kalıbıyla aynı); alarm günlüğünün sunucuya raporlanması.
- **Round 10 park kuyruğu (kararı OPH-195 verir):** alt görevler (`parent_task_id` —
  şema, API ve kaskadlı silme hazır, arayüz yok), görev rengi (`tasks.color_rgb` — widget
  kullanıyor, kullanıcı seçemiyor), **elle sıralama** (`sort_order` sıralamada kullanılıyor ama
  sürükleme yok), süre alanları (`estimated_minutes`/`actual_minutes`), `tasks.start_at`,
  proje ikonu/başlangıç-bitiş tarihi; Tamamlananlar ekranında arama + `cancelled`/`archived`
  sekmesi; Pano kartlarında kaydırarak silme (yatay pager jest çakışması); sunucu tarafı
  "tamamlananlar" ucu (bugün tamamen yerel replikadan okunuyor); geri alma olmayan silmeler
  (dosya, checklist öğesi, hatırlatıcı adımı).
- **Round 11 park kuyruğu — Hızlı Erişim (OPH-196'da kesinleşti, 2026-07-29):** Android
  sistem-geneli overlay düğmesi (SYSTEM_ALERT_WINDOW — ayrı izin ve istila, kendi turu;
  Messenger bile chat head'i Android 11'de Bubbles API'sine taşıdı, yani "uygulama dışı
  yüzen düğme" artık OS'un kendi kanalı üzerinden yapılan bir iştir); iOS'ta uygulama dışı
  yüzen düğme (OS üçüncü partiye izin vermez — yazılı sınır); kısayol klasörleri / iç içe
  liste (tek 50'lik liste için ikinci hiyerarşi seviyesi; Slack'in kendi önerisi de "3–5
  bölüm"); dış linklerde OG başlık çekme (unfurl proxy'ye bağlı); workspace-paylaşımlı ekip
  kısayol listesi (ADR-0018 "shared team list" alternatifi — additive, v2); emoji-picker
  paketi (tam ızgara — ADR gerektirir, gerekçesi yok); **kısayol renginde sınırsız palet**
  (`_ColorGridDialog`'un tüm `Colors.primaries` seti — DESIGN §23 Q8a: sınırsız fille
  kontrast garanti edilemiyor, kısayolda yalnız 10'luk palet sunuluyor); **yüzen düğme
  opaklık slider'ı** (AssistiveTouch'ta var; bizde tek anahtar + %40 sabiti yeterli sayıldı);
  kısayol satırından hedefi yeniden adlandırma (kısayol adı hedefin adı değildir — §4.12).
- **Round 11 park kuyruğu — AI (gerekçeler [AI.md](AI.md) + ADR-0019/0022/0023):**
  abonelik-OAuth entegrasyonu (üç sağlayıcıda da kapalı/bekleme listesi — üç ayda bir
  yeniden bakılır; `auth_mode='oauth_subscription'` rezerve); sohbette yazma araçları
  v1.5 (`complete_task`/`reschedule_task` onay-kapılı; **silme kalıcı olarak hariç**);
  yüksek-güvende onay kartını atlama anahtarı (v1.5 opt-in); senkron sohbet geçmişi
  (`conversation` varlığı — gizlilik duruşu değişikliği, bilinçli karar ister);
  sunucu-STT varsayılanı (OpenAI/Gemini ses — v1.5 ayarı); gerçek-zamanlı sesli sohbet
  (speech-to-speech); doğal-dil filtreleri → akıllı liste DSL'i (önce DSL); akıllı
  zamanlama (takvim boş/dolu akıl yürütmesi); otomatik etiket/öncelik önerisi;
  haftalık AI özet e-postası; barındırılan ücretli "AllisWell AI" katmanı (ürün kararı);
  paylaşımda dosya/görsel anlama; günlük/haftalık AI incelemesi + not özetleme +
  toplantı-notu→görevler (v1.5 adayları — Epic 19 çıkarım ucunu yeniden kullanır).
- **Round 17 park kuyruğu — Markdown (gerekçeler [MARKDOWN.md](MARKDOWN.md) §3):**
  `[[wikilink]]`'ler + geri bağlantılar (bir bağlantı indeksi ister — kendi başına bir
  özellik); graf görünümü, PDF üzerine not alma, atıf/BibTeX (**reddedildi** — başka bir
  ürün); yazma hedefleri (Ulysses); editör içi AI ("devam ettir", "yeniden yaz" — Epic 20'nin
  altyapısı hazır, ürün kararı); DOCX/ePub dışa aktarma; klasör/vault izleme (**reddedildi** —
  biz markdown'ı iyi okuyan bir görev uygulamasıyız, Obsidian değiliz); Vim/Emacs kısayolları
  ve özel CSS temaları (**reddedildi** — Rule 11, tek tasarım sistemi); göreli yollu görseller
  (`./x.png` bugün sebepli yer tutucuyla çiziliyor — OPH-247); bölünmüş görünümde satır eşlemeli
  senkron kaydırma (bugün oransal — `markdown_forge` reposunda `lib/src/edit/source_mode.dart`, OPH-248);
  dış dosyanın diskte değişmesini canlı izleme (bugün yalnız kaydetmede çatışma + elle
  `reprobe` — OPH-251).
- **Round 18 park kuyruğu (gerekçeler ADR-0031/0032):** **generic OIDC girişi**
  ([issue #2](https://github.com/mahirozdin/alliswell/issues/2) — Authentik/Keycloak/
  PocketID; meşru ve Firebase-sosyal-girişten farklı: sunucu yarısı ucuz çünkü ADR-0026'nın
  `src/lib/oauth-identity.js`'i zaten JWKS+issuer+audience doğrulaması ve subject-öncelikli
  hesap merdiveni taşıyor — iş "güvenilen issuer listesi + OIDC discovery'yi konfigürasyona
  açmak"; pahalı olan istemci yarısı: 6 Flutter platformunda authorization-code+PKCE tarayıcı
  akışı, deep-link dönüşü, ayar/doc yüzeyi. Tetikleyici: çok kullanıcılı workspace UI'ı
  açıldığında ya da talep birikince kendi epic'i olur); markdown'a renk sözdizimi (GFM'de yok
  — `==mark==` vurgusu var, gerisi Live/Delta tarafında; DESIGN §33 R6); Home/Projeler liste
  sıralaması (DESIGN §34 L5 yazılı sebepleri); notlar zip/dosya-başına toplu export (v1 JSON —
  OPH-266); API anahtarlarına scope'lar (v1 bilinçli scope'suz — ADR-0032 revizyonu ister);
  sürüm geçmişinde adlandırılmış/sabitlenmiş sürümler (Google Docs deseni; saklama
  inceltmesinden muafiyet mekanizması hazır, UI ürün kararı bekler); not etiketlerinin not
  push protokolüne girmesi (v1 bilinçli sınır: etiket yalnız REST `PUT /notes/:id/tags` ile
  yazılır, pull okur — OPH-261).
- Import from Todoist/TickTick/Apple Reminders; ICS export.
- Metrics endpoint (Prometheus), audit log UI, admin panel.
- E2E tests (Patrol/integration_test), F-Droid/TestFlight packaging.
- **İstemci yüklemelerinin taranması** (2026-09-24 incelemesi) — sunucunun kendi aldığı
  dosyalar bir uzantıda taranabiliyor; istemcinin presigned yüklemesi kovaya doğrudan gider
  ve taranmaz. Doğru çözüm kovada asenkron tarama + indirme kapısıdır (`files` satırında
  durum) — kendi turu.
- **Takvim v2:** Apple aynasının gelen yarısı — takvimde yapılan yabancı düzenlemeyi geri okuma
  (OPH-076'nın Google analoğu; çatışma politikası + ön plan yoklaması — OPH-078); CalDAV iCloud
  bağlayıcısı (yalnız tasarım, [CALDAV.md](CALDAV.md), `CALDAV_ENABLED` varsayılan kapalı — OPH-079).

### Ölçülmüş açıklar ve bilinen sınırlar (2026-09-26 temizliğinde toplandı — hiçbiri bir işe bağlı değildi)

- **Web teslimatı Kapalı iken alarm bandı** — Kapalı düşürülen aboneliği `webPushOff` diye
  raporluyor: bant dırdır ediyor ve "Tekrar kontrol et" kullanıcının Kapalı seçimine rağmen
  yeniden abone ediyor (`gateway_web.alarmSupport`, OPH-316'nın modu okunmuyor). 2026-09-26'da
  #19 turunda ölçüldü.
- **OPH-337** — `LocalKv` okunamazsa "Gizli widget" (ve bildirim gizliliği) hata vermeden
  "hiç ayarlanmamış" okunur → başlıklar widget'a yazılabilir.
- **OPH-226** — AI bağlantısının `baseUrl`'i korumasız bir SSRF yüzeyi (bilinçli kabul; yalnız
  SECURITY.md "AI ayarlarını güvenilen kullanıcılara açın" diyor).
- **ADR-0038 §8** — iOS başsız uyanış ertelendi: kilitli iPhone Keychain'i okuyamıyor
  (`WhenUnlocked`); erişilebilirlik değişikliği kendi güvenlik ADR'sini + yeniden anahtarlama
  göçünü ister.
- **OPH-025** — web'de httpOnly refresh-cookie sertleştirmesi (web oturumu bugün localStorage'da,
  `LocalKvSecretStore`).
- **OPH-324 takibi** — release APK'nın `res/raw` seslerini gerçekten taşıdığını ölçen artefakt
  kapısı hiç yazılmadı (`scripts/android/assert-permissions.sh` kalıbı).
- **OPH-236 (ikon)** — `scripts/design/branding_icons.py --check` hiçbir CI iş akışına bağlı değil.
- **OPH-193** — `check:i18n` yalnız literal kalıpları tarar; `Text(değişken)` ile basılan ham
  enum'u (`Text(project.status)`) göremez — kural ya da lint yok.
- **OPH-318** — uygulama dili değişince Android bildirim kanalının adı eski dilde kalıyor (önce
  ölç: aynı id'yle `createNotificationChannel` adı güncelleyebilir).
- **OPH-336** — widget yapılandırma sayfasının kendi etiketleri ("List", açıklama) İngilizce;
  native metaveri uygulamanın çevirisine ulaşmıyor.
- **OPH-181** — Android'de yüklenen özel ses bildirim kanalının sesi olamaz (FileProvider gerekir;
  bugün yalnız uygulama içi alarmda çalar); AlarmKit'in container'daki (`Library/Sounds`) sesi erken
  iOS 26'da çalmama raporu ölçülmedi — "çalmazsa paketli sese düş" yolu yok.
- **OPH-126** — oturum açılışında uygulama dilini `users.locale`'den tohumlama.
- **OPH-110** — kaskadlı arşivden çıkarma projenin TÜM arşivli öğelerini geri getirir (v1
  sadeleştirmesi; kaskadın dokunduklarını izlemek yeni kolon ister).
- **OPH-261** — proje arşiv kaskadı domain katmanında değil (`routes/projects.js`); MCP'de proje
  arşivleme bu yüzden yok.
- **OPH-168** — Pano: "2/5" konum etiketi ve dikey kenar otomatik kaydırması v1'den kırpıldı.
- **OPH-081** — drift'in üretilmiş şema-test aracına dönüş (drift_dev ↔ drift sürümleri
  hizalanınca); bugün göç testleri elle.
- **OPH-245** — `imageCache` bayt ölçümü hiç alınmadı (büyük fotoğraflarda bellek davranışı varsayım).
- **OPH-256** — macOS Release dağıtım imzası (Developer ID + noterleme) kararı verilmedi.
- **OPH-227** — README/mağaza için AI bubble ve onay kartı ekran görüntüleri yok.
- **`docs/SELF-HOSTING.md` §4** — yükseltme öncesi yedek komutunda `--no-tablespaces` eksik
  (§4b'dekinde var); PROCESS yetkisiz kullanıcıda korkutucu ama zararsız bir "Error:" basar.
