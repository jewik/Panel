# FastFolder — план переработки логики refresh

Дата: 29.10.2026
Статус: план. Реализация — после согласования.
Связанные документы: `fast-folder-feature-plan.md`, `fixes-1.md`, `fixes-2.md`.

## 1. Цель

Сделать refresh **независимым для каждой папки**: папка, которая уже проверена, сразу становится доступной на полке и в настройках, независимо от того, что остальные папки ещё проверяются или висят на сетевом томе.

Ожидаемое поведение:

| Ситуация | Сейчас | Должно быть |
|---|---|---|
| 5 локальных + 1 сетевой недоступный | Полка пустая/недоступная, спиннер, клики заблокированы, пока сетевой не отвалится по системному таймауту | 5 локальных появляются сразу (< 1 с), сетевой скрывается через 10 с; полка всё это время интерактивна |
| Папка была недоступна, стала доступна | Статус меняется только в самом конце общего refresh | Статус меняется сразу, как только её собственный результат пришёл |
| Первый запуск / открытие пресета | Пока refresh не завершился — все папки недоступны | Папки показываются сразу в последнем известном состоянии, обновление идёт фоном |
| Папка удалена во время refresh | Возможен «фантомный» id в `unavailableFolderIDs` | Состояние удалённой папки вычищается, поздний результат игнорируется |
| Повторный `onAppear` (home → fastfolder → settings) | Второй refresh молча глотается guard'ом | Уже проверяемые папки не перезапускаются, остальные — проверяются |
| Индикация загрузки | Полноэкранный оверлей «Refreshing…» с текстом | Индикатор по центру иконки каждой проверяемой папки, без текстов (см. §6.4) |

## 2. Почему сейчас всё «недоступно»

Четыре независимые причины, все надо устранить:

1. **`unavailableFolderIDs` присваивается один раз в конце** (`FastFolderStore.swift:143`). Пока общий refresh не завершён, в множестве остаётся прошлый (устаревший) снимок: успешно обновлённые папки не «возвращаются», а ранее недоступные не «появляются».
2. **`isRefreshing` — глобальный флаг**, который блокирует всю полку: `.disabled(store.isRefreshing)` + полноэкранный оверлей «Refreshing…» (`FastFolderView.swift:36-43`). Даже если папка уже готова, UI её не даёт нажать.
3. **`withTaskGroup` ждёт все дочерние задачи**. `refresh()` не возвращается, пока не завершится самая медленная папка, поэтому `isRefreshing` (и п.2) висит бесконечно долго. Внутренний `withTimeout` этого не решает: при выходе из scope группа всё равно дожидается «зависшего» child'а, а `cancelAll()` не прерывает блокирующий syscall (`fixes-2.md` §3.1).
4. **`FastFolderBookmarkService` — actor**, а значит все вызовы сериализуются: пока один `getxattr`/резолв bookmark висит на сетевом томе, остальные папки даже не начинают проверяться. «Каждая папка в своей задаче» здесь не работает — очередь на акторе.

## 3. Целевая модель состояния

Вместо `unavailableFolderIDs: Set<ID>` — состояние на папку:

```swift
enum FastFolderAvailability: Equatable, Sendable {
    case unknown      // ещё не проверялась в этой сессии — показываем как есть
    case refreshing   // идёт проверка — показываем последнее известное состояние
    case available
    case unavailable
}
```

Правила отображения:

- `.unknown` — папка видна (оптимистично: она была сохранена пользователем);
- `.refreshing` — папка видна в последнем известном состоянии + маленький индикатор, кликабельна;
- `.available` — видна;
- `.unavailable` — скрыта с полки, приглушена в настройках, доступны retry и удаление.

Из этого следует, что «всё недоступно» возможно только когда **все** папки явно получили `.unavailable`, а не потому что где-то идёт refresh.

## 4. Изменения в `FastFolderStore`

### 4.1 Состояние

```swift
@MainActor
@Observable
final class FastFolderStore {
    static let maximumFolderCount = 8
    nonisolated private static let refreshTimeout: Duration = .seconds(10)

    private(set) var folders: [FastFolder] = []
    private(set) var availability: [FastFolder.ID: FastFolderAvailability] = [:]

    @ObservationIgnored private let storage: FastFolderStorage
    @ObservationIgnored private let bookmarkService: FastFolderBookmarkServiceProtocol

    /// Текущая попытка на папку: защищает от применения устаревших результатов.
    @ObservationIgnored private var attempts: [FastFolder.ID: UUID] = [:]
    /// Задача загрузки (unstructured: refresh её не ждёт).
    @ObservationIgnored private var tasks: [FastFolder.ID: Task<Void, Never>] = [:]
    /// Сторож таймаута: реально ограничивает время ожидания.
    @ObservationIgnored private var watchdogs: [FastFolder.ID: Task<Void, Never>] = [:]
```

`isRefreshing` остаётся, но становится вычисляемым (для спиннера в тулбаре настроек):

```swift
    func availability(of id: FastFolder.ID) -> FastFolderAvailability {
        availability[id] ?? .unknown
    }

    var isRefreshing: Bool {
        availability.values.contains(.refreshing)
    }

    var availableFolders: [FastFolder] {
        folders.filter { availability(of: $0.id) != .unavailable }
    }

    var unavailableFolders: [FastFolder] {
        folders.filter { availability(of: $0.id) == .unavailable }
    }
```

### 4.2 Refresh: по папке, без ожидания, с настоящим таймаутом

```swift
    /// Запускает проверку всех папок, которые сейчас не проверяются. Не ждёт результата.
    func refresh() {
        for folder in folders {
            refresh(folderID: folder.id)
        }
    }

    func refresh(folderID: FastFolder.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        guard attempts[folderID] == nil else { return }   // уже проверяется — не дублируем

        let token = UUID()
        attempts[folderID] = token
        availability[folderID] = .refreshing

        let service = bookmarkService

        tasks[folderID] = Task { [weak self] in
            let result = await Self.load(folder, using: service)
            self?.finish(folderID: folderID, token: token, result: result)
        }

        watchdogs[folderID] = Task { [weak self] in
            try? await Task.sleep(for: Self.refreshTimeout)
            self?.finish(folderID: folderID, token: token, result: .timedOut)
        }
    }
```

Ключевые свойства:

- `refresh()` **синхронный и возвращается сразу** — вызывающая вью больше ничего не блокирует;
- каждая папка — своя `Task`, результаты не собираются «пачкой»;
- сторож не ждёт загрузку: по истечении 10 с папка помечается `.unavailable`, даже если syscall всё ещё висит;
- `token` гарантирует, что поздний результат «протухшей» попытки не перезапишет состояние.

### 4.3 Применение результата

```swift
    private enum LoadResult: Sendable {
        case refreshed(bookmark: Data, snapshot: FolderSnapshot)
        case failed
        case timedOut
    }

    private func finish(folderID: FastFolder.ID, token: UUID, result: LoadResult) {
        guard attempts[folderID] == token else { return }   // устаревшая попытка

        attempts[folderID] = nil
        tasks[folderID] = nil
        watchdogs[folderID]?.cancel()
        watchdogs[folderID] = nil

        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            availability[folderID] = nil                    // папку удалили во время refresh
            return
        }

        switch result {
        case .refreshed(let bookmark, let snapshot):
            let previous = folders[index]
            folders[index].bookmark = bookmark
            folders[index].name = snapshot.name
            folders[index].tags = snapshot.tags
            folders[index].tagColorIndex = snapshot.tagColorIndex
            availability[folderID] = .available

            if folders[index] != previous {
                storage.save(folders)                       // сохраняем сразу, а не в конце
            }

        case .failed, .timedOut:
            availability[folderID] = .unavailable
        }
    }
```

Побочный плюс: сохранение теперь происходит по факту изменения каждой папки. Раньше зависшая папка означала, что **ничего** не сохранится.

### 4.4 Загрузка (не изолирована на MainActor)

```swift
    private nonisolated static func load(
        _ folder: FastFolder,
        using service: FastFolderBookmarkServiceProtocol
    ) async -> LoadResult {
        do {
            let resolved = try await service.resolve(folder.bookmark)
            let bookmark = resolved.isStale
                ? try await service.makeBookmark(for: resolved.url)
                : folder.bookmark
            let snapshot = try await service.snapshot(of: resolved.url)

            return .refreshed(bookmark: bookmark, snapshot: snapshot)
        } catch {
            Log.service.error(
                "FastFolder refresh failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed
        }
    }
```

`withTimeout` и `FolderRefreshOutcome` удаляются: таймаут теперь реализован сторожем, а не группой задач.

### 4.5 Остальные методы

- `addFolders(_:)` — после успешного добавления сразу `availability[folder.id] = .available` (snapshot уже получен, лишний refresh не нужен).
- `open(_:)` — при успехе `availability[folder.id] = .available`, при ошибке `.unavailable` (сейчас пишет в `unavailableFolderIDs`).
- `removeFolder(id:)` — отменить попытку и вычистить состояние:
  ```swift
  attempts[id] = nil
  tasks[id]?.cancel(); tasks[id] = nil
  watchdogs[id]?.cancel(); watchdogs[id] = nil
  availability[id] = nil
  ```
- `removeAll()` — то же для всех id.
- `init` — `availability` остаётся пустым: загруженные из хранилища папки получают `.unknown` и видны сразу.

## 5. Изменения в сервисе: actor → `Sendable` struct + concurrent queue

Причина — п.4 из §2: actor сериализует вызовы, поэтому «параллельный» refresh на самом деле последовательный, и одна зависшая папка блокирует все остальные.

```swift
protocol FastFolderBookmarkServiceProtocol: Sendable {
    func makeBookmark(for url: URL) async throws -> Data
    func resolve(_ bookmark: Data) async throws -> (url: URL, isStale: Bool)
    func snapshot(of url: URL) async throws -> FolderSnapshot
}

struct FastFolderBookmarkService: FastFolderBookmarkServiceProtocol {
    private let queue = DispatchQueue(
        label: "com.panel.fastfolder.bookmark",
        qos: .userInitiated,
        attributes: .concurrent
    )

    func snapshot(of url: URL) async throws -> FolderSnapshot {
        try await perform { try Self.snapshotSync(of: url) }
    }

    // ... makeBookmark / resolve аналогично

    private func perform<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
```

Свойства:

- блокирующий syscall не занимает cooperative-поток и не сериализуется с другими папками;
- `startAccessingSecurityScopedResource()` / `defer stop` остаются внутри одного замыкания на одном потоке — семантика не меняется;
- протокол не меняется, store правится минимально.

Отвергнутые альтернативы:

- **actor + `nonisolated` методы** — блокирующий вызов уедет в cooperative pool и будет голодать его;
- **actor на папку** — плодит объекты и не решает проблему с `snapshot`, который тоже блокирующий;
- **`Task.detached` на папку** — та же проблема cooperative pool, что и выше.

## 6. Изменения в UI

### 6.1 Полка — `FastFolderView` / `FastFolderItemView`

- убрать `.disabled(store.isRefreshing)` и полноэкранный оверлей «Refreshing…» целиком — вместе с капсулой и текстом (`FastFolderView.swift:36-43, 51-66`), см. §6.4;
- `FastFolderItemView` принимает `isRefreshing: Bool` (узкий параметр через `init`, §3 RULES);
- при `.refreshing` по центру иконки показывается индикатор загрузки, последнее известное состояние папки остаётся читаемым (§6.4);
- клик по папке в `.refreshing` разрешён (открытие само резолвит bookmark);
- плейсхолдеры:
  - `folders.isEmpty` → «Add folders in Settings»;
  - `availableFolders.isEmpty && !store.isRefreshing` → «Folders unavailable»;
  - иначе — полка (в т.ч. пока идёт refresh).

### 6.2 Настройки — `FastFolderSettingsView` / `FastFolderSettingsItemView`

- тулбар: спиннер при `store.isRefreshing` — оставить как есть (это не текст);
- item принимает `availability` и рисует три состояния: индикатор загрузки по центру иконки (`.refreshing`, §6.4), обычная иконка (`.available`/`.unknown`), `folder.badge.questionmark` + `opacity 0.4` (`.unavailable`);
- у недоступной папки — retry: клик по чипу → `store.refresh(folderID: folder.id)`, `.help("Retry")`;
- кнопка удаления активна всегда.

### 6.3 Точки вызова

`refresh()` перестаёт быть `async`:

- `FastFolderView.swift:44-48` → `.task { store.refresh() }` (заодно снимает замечание `fixes-2.md` §4.4);
- `FastFolderSettingsView.swift:25-29` → `.task { store.refresh() }`;
- кнопка Refresh → `store.refresh()`.

Важно: отмена `.task` при исчезновении вью **не** отменяет refresh. Это соответствует §7 RULES — жизненным циклом владеет store (контейнер), а не подписчик.

### 6.4 Индикация загрузки (единая для полки и настроек)

Правило: **во время refresh каждая проверяемая папка показывает анимацию загрузки по центру своей иконки; никаких текстов про загрузку в UI нет.**

- Индикатор — `ProgressView().controlSize(.small)` **по центру иконки**, через `ZStack` поверх `Image(systemName: "folder.fill")`.
- Иконка под индикатором остаётся видимой и приглушается (`opacity 0.35` на полке, `0.4` в настройках) — так видно, какая именно папка грузится и какого она цвета.
- Тексты убрать/не добавлять: `Text("Refreshing…")` и капсула с ним удаляются из `FastFolderView.swift:51-66`; в настройках не появляются «Preparing…», «Loading…», «Checking…», «Refreshing…» и любые другие подписи состояния.
- Глобальных индикаторов загрузки нет. Единственное исключение — уже существующий `ProgressView` в тулбаре настроек (он без текста).
- Переход: `.animation(.easeOut(duration: 0.15), value: isRefreshing)` на элементе, чтобы появление/исчезновение индикатора не дёргалось.
- В настройках индикатор не перекрывает кнопку удаления (кнопка остаётся выше по z-order).
- Доступность (опционально, не видимый текст): `.accessibilityValue("Refreshing")` при `.refreshing`, чтобы состояние озвучивалось VoiceOver.

Эскиз элемента (пример для полки; hover-эффекты и тень иконки сохраняются как сейчас):

```swift
ZStack {
    Image(systemName: "folder.fill")
        .font(.system(size: 50, weight: .regular))
        .foregroundStyle(tagColor)
        .opacity(isRefreshing ? 0.35 : 1)

    if isRefreshing {
        ProgressView()
            .controlSize(.small)
            .transition(.opacity)
    }
}
.animation(.easeOut(duration: 0.15), value: isRefreshing)
```

## 7. Файлы

| Файл | Что меняется |
|---|---|
| `Services/FastFolderBookmarkService.swift` | `actor` → `Sendable` struct + concurrent queue; `perform`-хелпер; sync-реализации остаются приватными |
| `ViewModels/FastFolderStore.swift` | `availability`, `attempts`, `tasks`, `watchdogs`; новый `refresh()`/`refresh(folderID:)`/`finish`/`load`; удаление `withTimeout` и `FolderRefreshOutcome`; правки `addFolders`/`open`/`remove*` |
| `Views/FastFolderView.swift` | снять глобальную блокировку и оверлей «Refreshing…» с текстом, per-item индикатор (§6.4) |
| `Views/FastFolderItemView.swift` | параметр `isRefreshing`, индикатор по центру иконки, без текстов |
| `Views/FastFolderSettingsView.swift` | `.task`, вызовы `refresh()`, передача состояния в item |
| `Views/FastFolderSettingsItemView.swift` | три состояния + retry, индикатор по центру иконки, без текстов |
| `Views/FastFolderPreviewSupport.swift` | в `PreviewBookmarkService` добавить `delay` на запись, чтобы в preview воспроизвести «одна папка висит, остальные готовы»; весь файл — под `#if DEBUG` (`fixes-2.md` §2.3) |

`AppContainer` / `AppDelegate` не меняются: тип сервиса остаётся тем же.

## 8. Порядок реализации (приложение собирается после каждого шага)

1. **Сервис**: `actor` → `Sendable` struct + concurrent queue. Протокол без изменений. Сборка + ручная проверка, что папки открываются/читаются как раньше.
2. **Store**: добавить `availability`/`attempts`/`tasks`/`watchdogs`, переписать `refresh`, удалить `withTimeout`/`FolderRefreshOutcome`, обновить `addFolders`/`open`/`remove*`. Вью пока не трогаем — они продолжат компилироваться после замены `await store.refresh()` на `store.refresh()`.
3. **Полка**: убрать глобальный disable и оверлей «Refreshing…», добавить per-item индикатор по центру иконки (§6.4).
4. **Настройки**: три состояния item + retry, индикатор по центру иконки, без текстов.
5. **Preview support**: задержки, `#if DEBUG`.
6. **Чистка**: `unavailableCount` (мёртвый), закомментированный код в `FastFolderItemView.swift:53`.
7. Ручные сценарии из §10.

## 9. Риски и как их снимаем

| Риск | Решение |
|---|---|
| Каждый зависший том держит поток очереди | папок ≤ 8; при росте лимита — `OperationQueue(maxConcurrentOperationCount:)` вместо `DispatchQueue` |
| Поздний результат после таймаута перезапишет состояние | `token` в `attempts`; в `finish` проверка токена |
| Задача-«сирота» продолжает работать после таймаута | это осознанно: результат отбрасывается, завершение логируется на debug-уровне |
| `Task {}` внутри `@MainActor` store | тело задачи только ждёт; блокирующая работа — в сервисной очереди, MainActor не занят |
| Дубли refresh при частых `onAppear` | guard по `attempts[folderID]` — уже проверяемая папка не перезапускается |
| Сохранение на каждую папку | ≤ 8 маленьких JSON; выигрыш — данные не теряются из-за зависшей папки |
| Наблюдаемость `availability` | словарь — обычное `@Observable`-свойство, `isRefreshing`/`availableFolders` читают его, инвалидация остаётся гранулярной |

## 10. Проверка

Сборка:

```bash
xcodebuild -project Panel.xcodeproj -scheme Panel -destination 'platform=macOS' build
```

Ручные сценарии:

1. 5 локальных папок + 1 на недоступном SMB: 5 появляются сразу, шестая скрывается через ~10 с; полка кликабельна всё время.
2. Все локальные: появляются почти одновременно, без «мигания» недоступности.
3. Сетевой том вернулся: следующий refresh возвращает папку на полку.
4. Удалить папку, пока она в `.refreshing`: нет фантомных id, нет падения, `isRefreshing` корректно сбрасывается.
5. Переключение home → fastfolder → settings: папки не перезапускаются повторно, лишних запросов нет.
6. Первый запуск: сохранённые папки видны сразу, затем обновляются.
7. Настройки: у недоступной папки работает retry, удаление активно; спиннер только на проверяемой папке.
8. Refresh одной папки сохраняется в `UserDefaults`, даже если другая всё ещё висит.
9. Индикация: во время refresh у каждой проверяемой папки крутится спиннер по центру иконки; никаких текстов состояния на полке и в настройках.

Логи для проверки: `FastFolder refresh finished` заменить на per-folder (`refreshed/unavailable/timed out` с id и длительностью) — иначе по логам не видно независимости.

Grep-проверки:

```bash
# текстов про загрузку в UI быть не должно
grep -rn "Refreshing\|Preparing\|Loading\|Checking" Panel/Features/FastFolder/Views
# индикатор загрузки — только per-item
grep -rn "ProgressView" Panel/Features/FastFolder/Views
```

## 11. Вне объёма

- `MainActor.run` внутри actor и вынос открытия Finder в отдельный presenter — `fixes-2.md` §2.1;
- `NSOpenPanel` из вью в picker-сервис — `fixes-2.md` §2.2;
- единые метрики вёрстки (76/96/100/80) — `fixes-2.md` §4.5;
- параллелизация `addFolders` (сейчас последовательный цикл по URL);
- FSEvents / live-обновление статуса;
- таймаут на `open(_:)` (сейчас без ограничения; при желании переиспользует тот же механизм попыток).
