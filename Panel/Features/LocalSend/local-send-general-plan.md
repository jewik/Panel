# LocalSend — пакет поэтапных планов нативной Swift-реализации

## 1. Результат

При исполнении создать каталог `Panel/Features/LocalSend/` с главным roadmap и независимыми планами:

```text
Panel/Features/LocalSend/
├── README.md
├── localsend-0-protocol-baseline.md
├── localsend-1-identity-tls.md
├── localsend-2-registration-server.md
├── localsend-3-multicast-discovery.md
├── localsend-4-file-preparation.md
├── localsend-5-upload-engine.md
├── localsend-6-share-ui.md
├── localsend-7-direct-address.md
└── localsend-8-hardening-release.md
```

`README.md` содержит зависимости между частями, статусы и зафиксированные продуктовые решения. Каждый нумерованный документ можно отдельно исследовать, согласовывать, реализовывать и проверять без переписывания остальных.

Перед детализацией каждой части обязательно повторно проверить актуальный `main`, последний release и changelog официальных репозиториев:

- [localsend/localsend](https://github.com/localsend/localsend)
- [localsend/protocol](https://github.com/localsend/protocol)

В документе фиксировать дату исследования, commit SHA, версию протокола, просмотренные файлы и отличия от предыдущего исследования. Реализация части начинается только после устранения всех открытых решений в её документе.

## 2. Независимые части

### 0. Protocol baseline и dependency spike

- Зафиксировать LocalSend v2.2, wire DTO, маршруты, статусы ошибок и JSON fixtures.
- Проверить `protocol/README.md`, `CHANGELOG.md`, `packages/core/src/http/dto_v2.rs`, `model/discovery.rs`, `model/transfer.rs`.
- Подтвердить стек: Foundation, Network, Security, CryptoKit и точечная зависимость `swift-certificates`; другие HTTP/network packages не добавлять без отдельной поправки плана.
- Spike должен доказать создание RSA-2048 self-signed identity, импорт в Keychain/Security и использование одним identity для client/server TLS.
- Результат: таблица совместимости, выбранные версии SPM и тестовый certificate fixture. Продуктовый код не добавлять до успешного spike.

### 1. Identity и TLS

- Реализовать постоянную identity: RSA-2048, `CN=LocalSend User`, private key в Keychain, сертификат в DER.
- Fingerprint — SHA-256 DER, uppercase hex; новая identity создаётся только при отсутствии или повреждении сохранённой.
- TLS-клиент обязан проверять self-signature, срок действия и ожидаемый fingerprint во время handshake, до отправки HTTP body.
- Поддержать mTLS client credential; HTTPS является единственным разрешённым transport в v1.
- Исследовать `crypto/cert.rs`, `http/client/server_cert_verifier.rs`, `http/server/common/client_cert_verifier.rs`.
- Готовность: identity переживает перезапуск; неверный fingerprint завершает handshake до передачи metadata.

### 2. Registration server

- Реализовать небольшой HTTPS server через `NWListener`, без общего web-фреймворка.
- Маршруты sender-only: `POST /api/localsend/v2/register`, `GET /info`, `POST /cancel`.
- Слушать `53317`; при конфликте выбирать свободный порт и объявлять фактическое значение.
- Ограничить размер headers/body, валидировать method/path/content-length, закрывать malformed и oversized запросы.
- Для HTTPS требовать client certificate; fingerprint сертификата должен совпадать с `fingerprint` payload.
- Добавить App Sandbox Incoming/Outgoing Connections и `NSLocalNetworkUsageDescription`.
- Исследовать актуальные `http/server/mod.rs`, `server/v2.rs`, routing и DTO.
- Готовность: официальный LocalSend успешно регистрируется; spoofed payload и неверный client certificate отвергаются.

### 3. Multicast discovery

- Реализовать actor с отдельными UDP sockets на каждый подходящий IPv4/IPv6 interface, повторяя актуальную стратегию LocalSend.
- IPv4: `224.0.0.167:53317`; IPv6 extension: `ff12::fd3a:e420`; TTL/hops = 1.
- Отправлять announce burst с актуальными задержками официального core; собственные сообщения игнорировать по fingerprint.
- На чужой announce отправлять pinned HTTPS `/register`; входящие `/register` обновляют device store.
- Дедупликация по certificate fingerprint; хранить IPv6 scope ID; VPN/виртуальный интерфейс не должен ломать остальные sockets.
- Сеть запускается при первом открытии Share и остаётся активной до завершения Panel; новое открытие Share запускает повторный scan.
- Исследовать `multicast/mod.rs`, `multicast/socket.rs`, `discovery/` и `model/discovery.rs`.
- Готовность: официальное приложение обнаруживается в обе стороны, дубликаты IPv4/IPv6 объединяются.

### 4. Подготовка файлов

- Отделить drop intake от сети: нормализовать `[URL]` в immutable transfer manifest.
- Поддержать файлы и рекурсивные каталоги; пустые каталоги не передавать.
- Не следовать symlink, не допускать `..`, абсолютных и выходящих за корень relative paths.
- Сформировать UUID file ID, размер, MIME через `UTType`, timestamps и SHA-256.
- Security-scoped доступ удерживать от подготовки manifest до окончания передачи.
- Ошибка чтения любого выбранного файла останавливает подготовку до `/prepare-upload`.
- Исследовать `model/transfer.rs` и актуальную логику send task официального приложения.
- Готовность: manifest детерминирован, большие файлы не загружаются целиком в память.

### 5. Upload engine

- Реализовать `prepare-upload → upload → cancel` с certificate pinning и mTLS.
- Поддержать PIN retry, partial acceptance, `204/400/401/403/409/422/429/500`.
- Передавать file body потоково; максимум три параллельных upload, общий и per-file progress.
- Один активный send session в v1; повторный drop предлагает отменить текущую передачу либо ждёт её завершения.
- Cancel закрывает текущие tasks и best-effort отправляет `/cancel`.
- Receiver `/cancel` проверяет IP/fingerprint/session перед отменой локальной отправки.
- Исследовать `http/client/v2.rs`, `http/client/mod.rs` и upload task официального приложения.
- Готовность: отправка файлов и каталогов в официальный LocalSend, PIN, reject, partial accept, checksum mismatch и cancel работают предсказуемо.

### 6. Общий Share UI

- Добавить preset `.localsend`; Добавть preset `.share` with `.localsend` and `.airdrop`.
- При drag на Panel открывать общий Share с целями:
    - AirDrop;
    - найденные HTTPS LocalSend devices;
    - сохранённые direct-address peers;
    - `Enter IP…`.
- HTTP peers показывать disabled с пояснением `Encryption is disabled on this device`.
- Ввести `@MainActor @Observable LocalSendStore`; сетевые компоненты остаются actors/services и публикуют typed events.
- UI-состояния: activating, scanning, preparing, awaiting approval, PIN required, transferring, completed, rejected, failed, cancelled.
- Во время ожидания и передачи включать несбрасываемый auto-pin Share; пользовательский pin не менять. После успеха снять auto-pin через 2 секунды; ошибка остаётся до Retry/Dismiss.
- Сначала реализовать UI на fake service, затем подключить networking.
- Обновить `AppContainer` и AppDelegate lifecycle через constructor/environment injection; никаких application singletons.
- Готовность: AirDrop не регрессирует, LocalSend progress не зависит от hover, previews не запускают сеть.

### 7. Direct address

- Добавить ввод IP/hostname и порта с default `53317`, включая bracketed IPv6 и scope ID.
- Выполнять TOFU probe через HTTPS `/info`; перед первой передачей показывать alias и fingerprint для подтверждения.
- Сохранять только успешно подтверждённые peers: address, port, alias, fingerprint, last-success date.
- При смене сертификата блокировать передачу до нового явного подтверждения.
- Историю хранить в `UserDefaults`; private key остаётся только в Keychain.
- Исследовать актуальную direct-IP логику LocalSend CLI и HTTP client.
- Готовность: передача работает при заблокированном multicast; подмена сертификата не принимается молча.

### 8. Hardening и release

- Провести повторный protocol-drift audit относительно commit SHA из части 0.
- Проверить sandbox, local-network prompt, firewall, Wi‑Fi/Ethernet, VPN, IPv4/IPv6, port conflict и перезапуск приложения.
- Логи не содержат file content, PIN, private keys и полные пользовательские пути.
- Проверить memory/energy на больших файлах, отмену приложения и потерю сети.
- Добавить Apache-2.0 attribution только если копируется код; реализация по спецификации без копирования не требует включения исходников LocalSend.
- Проверить известные security advisories и path traversal, даже несмотря на sender-only scope.
- Готовность: interoperability matrix пройдена минимум с официальным LocalSend на macOS и одном мобильном устройстве.

## 3. Общие интерфейсы и архитектура

- Стабильные модели: `LocalSendDevice`, `LocalSendEndpoint`, `LocalSendIdentity`, `LocalSendFile`, `LocalSendManifest`, `LocalSendTransferState`, `LocalSendError`.
- Сетевой фасад предоставляет typed `AsyncStream<LocalSendEvent>`, `start()`, `scan()`, `send(...)`, `submitPIN(...)`, `cancel()`, `stop()`.
- `LocalSendStore` — единственный observable источник UI-состояния; Views только читают состояние и вызывают actions.
- Composition Root владеет lifecycle; listener не останавливается из `deinit` View/Store.
- Alias v1: `Panel — <localized Mac name>`, fallback `Panel`; `deviceType = desktop`, `download = false`.
- Вне scope v1: приём файлов, Download API, HTTP transport, WebRTC/v3, v1 protocol, clipboard/text-only sharing и синхронизация через интернет.

Зависимости частей:

```text
0 → 1 → 2 → 3
0 → 4
1 + 4 → 5
2 + 3 + 5 → 6
1 + 5 → 7
6 + 7 → 8
```

Каждая часть должна собираться и тестироваться до начала следующей.

## 4. Тестирование

- Unit: Codable fixtures, fingerprint, certificate persistence, path normalization, directory traversal, MIME, checksums, error mapping и state transitions.
- Integration: loopback mTLS peer, register server, multicast sockets, upload streaming, partial acceptance, PIN и cancel.
- Security: неверный fingerprint/client certificate, oversized HTTP body, malformed JSON, changed TOFU certificate, symlink/path escape.
- UI: fake devices, scanning/empty/error/PIN/progress/completion, auto-pin, AirDrop fallback.
- Manual interoperability: официальный LocalSend текущего release, файлы 0 B/большие/Unicode, каталоги, Wi‑Fi/Ethernet, VPN, IPv6 и direct IP.
- Для каждой части её документ содержит собственные acceptance criteria и список тестов; общий `README.md` хранит итоговую матрицу статусов.

## 5. Формат каждого документа

Каждый `localsend-N-*.md` создаётся сначала как outline и при повторном исследовании расширяется по единому шаблону:

1. Цель и границы.
2. Prerequisites и зависимости.
3. Official-source snapshot: дата, release, commit SHA, просмотренные пути.
4. Findings и отличия от baseline.
5. Зафиксированные решения и публичные интерфейсы.
6. Пошаговая реализация.
7. Ошибки и security invariants.
8. Tests и acceptance criteria.
9. Open questions — перед реализацией раздел обязан быть пустым.
10. Статус: `outline → researched → agreed → implemented → verified`.

Изменения не коммитить автоматически.