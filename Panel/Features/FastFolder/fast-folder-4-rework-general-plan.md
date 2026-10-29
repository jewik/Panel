# FastFolder — единый план: переработка refresh + архитектурные правки

Дата: 29.10.2026

Статус: план. Реализация — после согласования.

Источники:

- `refresh-rework-plan.md` — поведение refresh (далее «план refresh»);
- `fixes-2.md` — ревью по `RULES-EN.md` и Swift 6 style (далее «ревью»);
- `fixes-1.md`, `fast-folder-feature-plan.md` — контекст.

Этот документ заменяет планы правок из обоих источников: он содержит все идеи по refresh и все архитектурные исправления, которые должны быть внедрены в том же проходе, плюс правила, которым подчиняется реализация. Исходные документы остаются в репозитории как история ревью.

---

## 1. Цель

1. Сделать refresh **независимым для каждой папки**: проверенная папка сразу доступна на полке и в настройках, независимо от того, что остальные папки ещё проверяются или висят на сетевом томе.
2. Закрыть нарушения RULES, которые находятся в том же коде, чтобы переработка refresh не закрепила их: скрытый `MainActor` в actor'е, AppKit во вью, preview-код в релизной сборке.

Ожидаемое поведение:

| Ситуация | Сейчас | Должно быть |
|---|---|---|
| 5 локальных + 1 сетевой недоступный | Полка пустая/недоступная, спиннер, клики заблокированы, пока сетевой не отвалится по системному таймауту | 5 локальных появляются сразу (< 1 с), сетевой скрывается через 10 с; полка всё это время интерактивна |
| Папка была недоступна, стала доступна | Статус меняется только в самом конце общего refresh | Статус меняется сразу, как только её собственный результат пришёл |
| Первый запуск / открытие пресета | Пока refresh не завершился — все папки недоступны | Папки показываются сразу в последнем известном состоянии, обновление идёт фоном |
| Папка удалена во время refresh | Возможен «фантомный» id в `unavailableFolderIDs` | Состояние удалённой папки вычищается, поздний результат игнорируется |
| Повторный `onAppear` (home → fastfolder → settings) | Второй refresh молча глотается guard'ом | Уже проверяемые папки не перезапускаются, остальные — проверяются |
| Индикация загрузки | Полноэкранный оверлей «Refreshing…» с текстом | Индикатор по центру иконки каждой проверяемой папки, без текстов (§8.4) |
| Изоляция и слои | `MainActor.run` внутри actor, `NSOpenPanel` во вью | Контракт изоляции в сигнатуре, AppKit — в platform-слое |

---

## 2. Диагноз

### 2.1 Почему refresh ведёт себя как «всё недоступно»

Четыре независимые причины, все устраняются:

1. **`unavailableFolderIDs` присваивается один раз в конце** (`FastFolderStore.swift:143`). Пока общий refresh не завершён, в множестве остаётся прошлый (устаревший) снимок: успешно обновлённые папки не «возвращаются», ранее недоступные не «появляются».
2. **`isRefreshing` — глобальный флаг**, блокирующий всю полку: `.disabled(store.isRefreshing)` + полноэкранный оверлей «Refreshing…» (`FastFolderView.swift:36-43,51-66`).
3. **`withTaskGroup` ждёт все дочерние задачи**. `refresh()` не возвращается, пока не завершится самая медленная папка, поэтому глобальный флаг висит бесконечно долго. `withTimeout` этого не решает: при выходе из scope группа дожидается «зависшего» child'а, а `cancelAll()` не прерывает блокирующий syscall (`fixes-2.md` §3.1).
4. **`FastFolderBookmarkService` — actor**, поэтому вызовы сериализуются: пока один `getxattr`/резолв bookmark висит на сетевом томе, остальные папки даже не начинают проверяться. «Каждая папка в своей задаче» не работает — очередь на акторе.

### 2.2 Архитектурные нарушения (по `RULES-EN.md`)

| § | Нарушение | Файл |
|---|---|---|
| 9 | `MainActor.run` спрятан в теле actor-метода `openInNewFinderWindow` — контракт изоляции не виден в сигнатуре | `Services/FastFolderBookmarkService.swift:98-113` |
| 5 | `NSOpenPanel`, `runModal`, `NSApp.activate` живут во вью; вью не только читает состояние и шлёт действия | `Views/FastFolderSettingsView.swift:119-143` |
| 4 / 11.6 | Preview-support компилируется в релизный бинарник; `#Preview` в `HomeUI` без `.environment(...)` падает | `Views/FastFolderPreviewSupport.swift`, `UIPresets/HomeUI.swift:21` |
| 5 / 11.1 | Слой сервиса совмещает platform-работу с UI-обязанностью «показать Finder» | `Services/FastFolderBookmarkService.swift:98` |

### 2.3 Дефекты поведения, не связанные с таймаутом

- **Дедуп не видит недоступные папки** (`FastFolderStore.swift:159-163`): `try? await resolve(...)` — путь недоступной папки не попадает в `knownPaths`, ту же физическую папку можно добавить второй раз.
- **Фантомные id**: удалённая во время refresh папка остаётся в `unavailableFolderIDs` (следствие п.1 выше).
- **Мёртвый API**: `unavailableCount` (`:86`) нигде не используется; `FastFolderRefreshError`, `FolderRefreshOutcome` и `withTimeout` уходят вместе с новым механизмом таймаута.
- **Мёртвый код**: закомментированный `.contentShape(...)` в `Views/FastFolderItemView.swift:53`.

### 2.4 Стилевые/консистентные замечания (Swift 6 style)

Проект **не в Swift 6 language mode** (`SWIFT_VERSION = 5.0`), но включены `SWIFT_APPROACHABLE_CONCURRENCY = YES` и `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Значит компилятор не поймает неявную изоляцию — все контракты объявляются явно.

1. Несогласованный порядок модификаторов: `nonisolated private static let` vs `private nonisolated static func`.
2. Неявный `Sendable` у `FastFolder` и `FastFolderAddOutcome` (пересекают границу nonisolated-кода).
3. Избыточный `@MainActor` на реализациях `FastFolderStorage` при дефолтной MainActor-изоляции.
4. `.onAppear { Task { … } }` вместо `.task`.
5. Дублирование и рассинхрон метрик вёрстки: `76×96` в item vs `shelfHeight = 100` с паддингом `10` → контент высотой 96 не влезает в 80.
6. `FinderTagColor.color` объявлен в `FastFolderItemView.swift`, используется и в настройках.
7. `withTimeout` — глобальная generic-функция в файле ViewModel (снимается удалением, см. §4).
8. Нейминг замыканий: `FastFolderItemView(folder:action:)` vs `onRemove` в settings-item.
9. `snapshot(of:)` читается лучше через `guard let … else { return fallback }`.
10. `FastFolderBookmarkServiceProtocol` — суффикс `Protocol` неидиоматичен, но это общая конвенция проекта: оставляем, заметка без действия.

---

## 3. Правила, которым подчиняется реализация

Это не рекомендации, а ограничения на каждое изменение из §5–§11.

| RULES | Требование | Как выполняется здесь |
|---|---|---|
| §1 | Никакого Service Locator | `.shared` остаётся только у системного `NSWorkspace` и только внутри `FinderPresenter`. В store/вью — никаких `.shared`. |
| §2 | Единый Composition Root | `FinderPresenter`, `FolderPicker`, `FastFolderBookmarkService` создаются в `AppContainer` и передаются через `init`. Поля — `let`. |
| §3 | UI через Environment, узкие параметры через `init` | Store/controller — `@Environment`. В item-вью передаются только `isRefreshing`/`availability`, `onOpen`/`onRetry`/`onRemove`, метрики. |
| §4 | Протоколы осмысленны при подстановке + локальные preview | `FinderPresenting`, `FolderPicking`, `FastFolderBookmarkServiceProtocol` имеют фейки. Все preview-support типы под `#if DEBUG`; `#Preview` строятся на локальных инстансах. |
| §5 | Слои только вниз: UI → ViewModel → Service → Platform | AppKit-диалог и открытие Finder — в platform-типах. Вью вызывает метод store. Store не знает про SwiftUI. |
| §6 | Типизированные события вместо строк | Новых событий нет: доступность папки — наблюдаемое состояние store, не `NotificationCenter`. |
| §7 | Lifecycle у владельца | Задачи refresh принадлежат store (контейнеру). Отмена `.task` вью **не** отменяет проверку — это осознанное следствие правила, а не утечка. |
| §8 | Синглтоны | Новых синглтонов нет. |
| §9 | Изоляция в сигнатуре | `FastFolderStore`, `FinderPresenter`, `FolderPicker` — явные `@MainActor` типы. Bookmark-сервис — `Sendable` struct без `MainActor`, блокирующая работа на собственной concurrent-очереди. Никаких `MainActor.run` внутри сервисов. |
| §10 | Observable-состояние без дублей | `statuses`/`refreshingIDs` — свойства `@Observable` store; вью не зеркалят их в `@State`. `@ObservationIgnored` только на сервисах, задачах и токенах попыток. |
| §11 | Чеклист фичи | Модель/сервис + ViewModel + View сохраняются; вью только читает и шлёт действия; preview без побочных эффектов. |
| §12 | Без «большого рефакторинга» | Пошаговый порядок из §12: приложение собирается после каждого шага. |

Дополнительные технические правила для этого кода:

- **Явный `Sendable`** на `FastFolder`, `FastFolderAddOutcome`, `FastFolderAvailability`, `FastFolderStatus`, `LoadResult`, `FinderTagColor`.
- **Единый порядок модификаторов**: `nonisolated private static let/func` (изоляция первой).
- **Никаких текстов про загрузку в UI.** Единственный глобальный индикатор — `ProgressView` в тулбаре настроек.
- **Таймаут 10 с** — единая константа `refreshTimeout`, без локальных дублей.
- **Логи per-folder**, без агрегированного «refresh finished».

---

## 4. Решения, принятые при сведении документов

Места, где источники расходились или где при сведении нашёлся дефект. Эти решения обязательны к исполнению.

1. **`withTimeout` удаляется, а не переносится** в `Panel/Extensions/` (ревью §4.7, §5.1). Таймаут реализуется сторожевой задачей в store: переносить нечего.
2. **Таймаут = 10 с** (план refresh), а не 15 с (ревью §3.1, §6). Критерий готовности из ревью «refresh завершается за ~15 с» читать как «за ~10 с».
3. **Состояние разделяется на два измерения**: последний известный статус (`statuses`) и факт проверки (`refreshingIDs`). Один enum `availability` для хранения не годится: retry недоступной папки переводил бы её в `.refreshing`, и она на 10 с «всплывала» бы на полку, чтобы потом снова исчезнуть. Наружу остаётся ровно тот же enum из плана refresh, но `.refreshing` — вычисляемый слой над статусом.
4. **`isRefreshing` больше не хранимое свойство** — вычисляется как «есть хотя бы одна проверяемая папка». `unavailableFolderIDs`, `unavailableCount`, `FolderRefreshOutcome`, `FastFolderRefreshError` удаляются.
5. **`AppContainer` меняется** (вопреки последней строке §7 плана refresh): тип bookmark-сервиса можно поменять без правки контейнера, но `FinderPresenter` и `FolderPicker` — новые зависимости, их надо собрать в Composition Root.
6. **`openInNewFinderWindow` уходит из `FastFolderBookmarkServiceProtocol`** в `FinderPresenting`. Следствие: `PreviewBookmarkService` перестаёт реализовывать этот метод, а preview получает `PreviewFinderPresenter`.
7. **`.task` вместо `.onAppear`**, но отмена задачи вью не отменяет refresh: задачи живут в store. Guard по `attempts[folderID]` коалесцирует повторный вызов по каждой папке отдельно, а не глотает весь refresh.
8. **Сохранение — на каждую папку** по факту изменения (план refresh §4.3), а не один раз в конце. При ≤ 8 папках это дешёво и не теряет данные из-за зависшего тома.
9. **Дедуп — best effort**: путь сравнивается по разрешённым bookmark'ам; для неразрешимых папок сравнивается `name`. Ложное совпадение имени возможно, поэтому случай логируется.
10. **`UIPresets/HomeUI.swift:12`** (полка и в `.home`, и в `.fastfolder`) — продуктовый вопрос, в этом плане не меняется; вынесен в §15.

---

## 5. Целевая модель состояния

Наружу — один enum на папку:

```swift
enum FastFolderAvailability: Equatable, Sendable {
    case unknown      // ещё не проверялась в этой сессии
    case refreshing   // идёт проверка, показываем последний известный статус
    case available
    case unavailable
}
```

Внутри store — два источника:

```swift
enum FastFolderStatus: Equatable, Sendable {
    case available
    case unavailable
}
```

Правила отображения:

- `.unknown` — папка видна (оптимистично: её сохранил пользователь);
- `.refreshing` — папка видна в последнем известном состоянии + индикатор, кликабельна;
- `.available` — видна;
- `.unavailable` — скрыта с полки, приглушена в настройках, доступны retry и удаление.

«Всё недоступно» возможно только когда **все** папки явно получили `.unavailable`, а не потому что где-то идёт refresh.

---

## 6. `FastFolderStore`

### 6.1 Состояние

```swift
@MainActor
@Observable
final class FastFolderStore {
    static let maximumFolderCount = 8
    nonisolated private static let refreshTimeout: Duration = .seconds(10)

    private(set) var folders: [FastFolder] = []
    /// Последний известный статус. Отсутствие записи == «ещё не проверялась».
    private(set) var statuses: [FastFolder.ID: FastFolderStatus] = [:]
    /// Папки, которые проверяются прямо сейчас.
    private(set) var refreshingIDs: Set<FastFolder.ID> = []

    @ObservationIgnored private let storage: FastFolderStorage
    @ObservationIgnored private let bookmarkService: FastFolderBookmarkServiceProtocol
    @ObservationIgnored private let finder: FinderPresenting
    @ObservationIgnored private let picker: FolderPicking

    /// Текущая попытка на папку: защищает от применения устаревших результатов.
    @ObservationIgnored private var attempts: [FastFolder.ID: UUID] = [:]
    /// Загрузка (unstructured: refresh её не ждёт).
    @ObservationIgnored private var tasks: [FastFolder.ID: Task<Void, Never>] = [:]
    /// Сторожевой таймаут: реально ограничивает ожидание.
    @ObservationIgnored private var watchdogs: [FastFolder.ID: Task<Void, Never>] = [:]
```

Вычисляемые свойства:

```swift
    func availability(of id: FastFolder.ID) -> FastFolderAvailability {
        if refreshingIDs.contains(id) {
            return .refreshing
        }

        switch statuses[id] {
        case .available?: return .available
        case .unavailable?: return .unavailable
        case nil: return .unknown
        }
    }

    var isRefreshing: Bool {
        !refreshingIDs.isEmpty
    }

    var availableFolders: [FastFolder] {
        folders.filter { statuses[$0.id] != .unavailable }
    }

    var unavailableFolders: [FastFolder] {
        folders.filter { statuses[$0.id] == .unavailable }
    }
```

`availableFolders` смотрит на `statuses`, а не на `availability`: проверяемая папка не должна менять видимость на полке. `canAddFolder` остаётся.

### 6.2 Refresh: по папке, без ожидания, с настоящим таймаутом

```swift
    /// Запускает проверку всех папок, которые сейчас не проверяются. Не ждёт результата.
    func refresh() {
        for folder in folders {
            refresh(folderID: folder.id)
        }
    }

    func refresh(folderID: FastFolder.ID) {
        guard let folder = folders.first(where: { $0.id == folderID }) else { return }
        guard attempts[folderID] == nil else { return }   // уже проверяется

        let token = UUID()
        attempts[folderID] = token
        refreshingIDs.insert(folderID)

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

Свойства:

- `refresh()` синхронный и возвращается сразу — вью ничего не блокирует;
- каждая папка — своя `Task`, результаты не собираются «пачкой»;
- сторож не ждёт загрузку: по истечении 10 с папка помечается `.unavailable`, даже если syscall висит;
- `token` гарантирует, что поздний результат протухшей попытки не перезапишет состояние;
- повторный вызов по уже проверяемой папке — no-op.

### 6.3 Применение результата

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
        refreshingIDs.remove(folderID)

        guard let index = folders.firstIndex(where: { $0.id == folderID }) else {
            statuses[folderID] = nil                       // папку удалили во время refresh
            return
        }

        switch result {
        case .refreshed(let bookmark, let snapshot):
            let previous = folders[index]
            folders[index].bookmark = bookmark
            folders[index].name = snapshot.name
            folders[index].tags = snapshot.tags
            folders[index].tagColorIndex = snapshot.tagColorIndex
            statuses[folderID] = .available

            if folders[index] != previous {
                storage.save(folders)                      // сохраняем сразу
            }

        case .failed, .timedOut:
            statuses[folderID] = .unavailable
        }
    }
```

Тайм-аут для ранее доступной папки тоже даёт `.unavailable` — это и есть «сетевой том скрывается через 10 с».

### 6.4 Загрузка

```swift
    nonisolated private static func load(
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

`withTimeout` и `FolderRefreshOutcome` удаляются. Тело `load` только ожидает: блокирующая работа уходит в очередь сервиса, MainActor не занят.

### 6.5 Остальные методы

- `init(storage:bookmarkService:finder:picker:)` — `statuses`/`refreshingIDs` пустые: загруженные папки получают `.unknown` и видны сразу.
- `addFolders(_:)` — после успешного добавления сразу `statuses[folder.id] = .available` (snapshot уже получен); дедуп по пути + fallback по `name` для неразрешимых папок (§7.3).
- `addFoldersViaPicker()` — `let urls = await picker.pickFolders()`, пустой результат → `nil`; иначе `addFolders(urls)`.
- `open(_:)` — при успехе `statuses[folder.id] = .available`, при ошибке `.unavailable`; Finder открывается через `finder`.
- `removeFolder(id:)` — отменить и вычистить:

  ```swift
  attempts[id] = nil
  tasks[id]?.cancel(); tasks[id] = nil
  watchdogs[id]?.cancel(); watchdogs[id] = nil
  refreshingIDs.remove(id)
  statuses[id] = nil
  ```

- `removeAll()` — то же для всех id.

```swift
    func open(_ folder: FastFolder) async {
        do {
            let resolved = try await bookmarkService.resolve(folder.bookmark)

            if resolved.isStale {
                let refreshed = try await bookmarkService.makeBookmark(for: resolved.url)

                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    folders[index].bookmark = refreshed
                    storage.save(folders)
                }
            }

            statuses[folder.id] = .available
            finder.openInNewFinderWindow(resolved.url)
        } catch {
            statuses[folder.id] = .unavailable
            Log.service.error(
                "FastFolder open failed for \(folder.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
```

### 6.6 Логирование

Агрегированная строка `FastFolder refresh finished` удаляется. Вместо неё — результат на папку и длительность:

```text
FastFolder refresh refreshed id=<uuid> name=<name> in 0.04s
FastFolder refresh unavailable id=<uuid> name=<name> in 0.11s
FastFolder refresh timed out id=<uuid> name=<name> after 10.00s
FastFolder refresh discarded late result for removed folder id=<uuid>
```

Длительность считается в `load`/стороже через `ContinuousClock`; поздний результат после таймаута логируется на debug-уровне.

---

## 7. Сервисы

### 7.1 Bookmark-сервис: `actor` → `Sendable` struct + concurrent queue

Причина — §2.1 п.4: actor сериализует вызовы, одна зависшая папка блокирует остальные.

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

    func makeBookmark(for url: URL) async throws -> Data {
        try await perform { try Self.makeBookmarkSync(for: url) }
    }

    func resolve(_ bookmark: Data) async throws -> (url: URL, isStale: Bool) {
        try await perform { try Self.resolveSync(bookmark) }
    }

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

- блокирующий syscall не занимает cooperative-поток и не сериализуется с другими папками;
- `startAccessingSecurityScopedResource()` / `defer stop` остаются внутри одного замыкания на одном потоке;
- `snapshot` переписывается на `guard let … else { return fallback }`;
- `openInNewFinderWindow` из протокола удаляется (§7.2).

### 7.2 `FinderPresenter` — MainActor в сигнатуре (RULES §9)

```swift
@MainActor
protocol FinderPresenting {
    func openInNewFinderWindow(_ url: URL)
}

@MainActor
final class FinderPresenter: FinderPresenting {
    func openInNewFinderWindow(_ url: URL) {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let selected = NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)

        if !selected {
            NSWorkspace.shared.open(url)
        }
    }
}
```

Store вызывает его напрямую (оба `@MainActor`), без `await` и без скрытого прыжка. Bookmark-сервис остаётся чистым platform-слоем без UI-обязанностей.

### 7.3 `FolderPicker` — AppKit из вью в platform-слой (RULES §5)

```swift
@MainActor
protocol FolderPicking {
    func pickFolders() async -> [URL]
}

@MainActor
final class FolderPicker: FolderPicking {
    func pickFolders() async -> [URL] {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose folders to add to FastFolders"

        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }

        return response == .OK ? panel.urls : []
    }
}
```

Асинхронный `begin` вместо `runModal()` убирает блокировку main-потока на время диалога. Если `begin` поведёт себя нестабильно в панельном окне — допустимый fallback: `runModal()` внутри `FolderPicker` (вью всё равно остаётся чистой), это фиксируется в коде комментарием, а не молча.

Дедуп в `addFolders` с учётом недоступных папок:

```swift
    var knownPaths = Set<String>()
    var unresolvedNames = Set<String>()

    for folder in folders {
        if let resolved = try? await bookmarkService.resolve(folder.bookmark) {
            knownPaths.insert(resolved.url.standardizedFileURL.path)
        } else {
            unresolvedNames.insert(folder.name)
        }
    }

    for url in urls {
        let path = url.standardizedFileURL.path

        if knownPaths.contains(path) || unresolvedNames.contains(url.lastPathComponent) {
            outcome.skippedDuplicates += 1
            Log.service.debug("FastFolder duplicate skipped for \(path, privacy: .public)")
            continue
        }
        // …
    }
```

### 7.4 `AppContainer`

```swift
    let fastFolderStore: FastFolderStore

    init() {
        // …
        let finder = FinderPresenter()
        let picker = FolderPicker()

        self.fastFolderStore = FastFolderStore(
            storage: UserDefaultsFastFolderStorage(),
            bookmarkService: FastFolderBookmarkService(),
            finder: finder,
            picker: picker
        )
    }
```

Порядок инициализации знает только root; все зависимости — `let` и через `init`.

### 7.5 Отвергнутые альтернативы

- **actor + `nonisolated` методы** для bookmark-сервиса — блокирующий вызов уедет в cooperative pool и будет его голодать.
- **actor на папку** — плодит объекты и не решает проблему с блокирующим `snapshot`.
- **`Task.detached` на папку** — та же проблема cooperative pool.
- **`withTimeout` в `Panel/Extensions/`** — см. §4 п.1: таймаут реализован сторожем, функция не нужна.

---

## 8. UI

### 8.1 Полка — `FastFolderView` / `FastFolderItemView`

- убрать `.disabled(store.isRefreshing)` и оверлей «Refreshing…» целиком, вместе с капсулой и текстом (`FastFolderView.swift:36-43,51-66`);
- `FastFolderItemView` принимает `isRefreshing: Bool` и `onOpen` (узкие параметры через `init`, RULES §3);
- при `.refreshing` по центру иконки — индикатор, последнее известное состояние остаётся читаемым (§8.4);
- клик по папке в `.refreshing` разрешён: `open` сам резолвит bookmark;
- плейсхолдеры:
  - `folders.isEmpty` → «Add folders in Settings»;
  - `availableFolders.isEmpty && !store.isRefreshing` → «Folders unavailable»;
  - иначе — полка (в том числе пока идёт refresh).

### 8.2 Настройки — `FastFolderSettingsView` / `FastFolderSettingsItemView`

- тулбар: `ProgressView` при `store.isRefreshing` — оставить как есть (без текста);
- item принимает `availability` и рисует три состояния:
  - `.refreshing` — индикатор по центру иконки, иконка приглушена;
  - `.available` / `.unknown` — обычная иконка;
  - `.unavailable` — `folder.badge.questionmark` + `opacity 0.4`;
- у недоступной папки retry: клик по чипу → `store.refresh(folderID: folder.id)`, `.help("Retry")`;
- кнопка удаления активна всегда и выше по z-order, чем индикатор.

### 8.3 Точки вызова

`refresh()` больше не `async`:

- `FastFolderView` → `.task { store.refresh() }`;
- `FastFolderSettingsView` → `.task { store.refresh() }`;
- кнопка Refresh → `store.refresh()`;
- кнопка Add → `Task { await store.addFoldersViaPicker() }`;
- удаление всех → `store.removeAll()`.

Отмена `.task` при исчезновении вью **не** отменяет refresh: жизненным циклом владеет store (RULES §7).

### 8.4 Индикация загрузки

Правило: **во время refresh каждая проверяемая папка показывает анимацию загрузки по центру своей иконки; никаких текстов про загрузку в UI нет.**

- индикатор — `ProgressView().controlSize(.small)` по центру иконки через `ZStack` поверх `Image(systemName: "folder.fill")`;
- иконка под индикатором видна и приглушена (`0.35` на полке, `0.4` в настройках) — видно, какая папка грузится и какого она цвета;
- тексты не добавляются: «Refreshing…», «Preparing…», «Loading…», «Checking…» запрещены и на полке, и в настройках;
- глобальных индикаторов нет; единственное исключение — `ProgressView` в тулбаре настроек;
- переход: `.animation(.easeOut(duration: 0.15), value: isRefreshing)`;
- в настройках индикатор не перекрывает кнопку удаления;
- доступность: `.accessibilityValue("Refreshing")` при `.refreshing` (не видимый текст).

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

Hover-эффекты, тень иконки и `contentShape` сохраняются.

### 8.5 Метрики вёрстки

Один источник — `Views/FastFolderMetrics.swift`:

```swift
enum FastFolderMetrics {
    static let itemWidth: CGFloat = 76
    static let itemHeight: CGFloat = 96
    static let itemSpacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let verticalPadding: CGFloat = 4
    static var shelfHeight: CGFloat { itemHeight + verticalPadding * 2 }

    static let placeholderWidth: CGFloat = 400
    static let maximumShelfWidth: CGFloat = 900

    enum Settings {
        static let itemWidth: CGFloat = 86
        static let itemHeight: CGFloat = 84
        static let iconWidth: CGFloat = 70
        static let iconHeight: CGFloat = 54
        static let captionWidth: CGFloat = 72
    }
}
```

Обязательно: `shelfHeight` вычисляется из `itemHeight`, а не задаётся числом 100 — иначе элемент 96 pt лежит в скролле высотой 80 pt и обрезается. После правки проверить, что полка и настройки помещаются в панель (пресеты `FastFolderUI`/`SettingsUI`, высота 150).

---

## 9. Preview, `#if DEBUG`, пресеты

- Весь `Views/FastFolderPreviewSupport.swift` (или его переезд в `Views/Preview/`) — под `#if DEBUG`: `InMemoryFastFolderStorage`, `PreviewBookmarkService`, `PreviewFastFolder`, `makePreviewFastFolderStore`, фейки `PreviewFinderPresenter` / `PreviewFolderPicker`.
- `PreviewBookmarkService` получает настраиваемую `delay` на запись, чтобы воспроизвести «одна папка висит, остальные готовы»; `isAvailable == false` даёт `.failed`, задержка — `.refreshing`.
- `makePreviewFastFolderStore` передаёт фейковые finder/picker.
- `UIPresets/HomeUI.swift:21` — добавить `.environment(makePreviewFastFolderStore([...]))` и `.environment(PanelController(panelState: PanelState()))`; сейчас preview падает.
- Существующие `#Preview` в `FastFolderUI`/`SettingsUI` остаются валидными; проверить после смены инициализатора store.

Фейки возвращают управление мгновенно, но с задержками, чтобы индикатор был виден и не «мигал».

---

## 10. Архитектурные и стилевые правки

Приоритет P0 — без них refresh не работает; P1 — нарушения RULES; P2 — полировка.

| # | Правка | Файл | P |
|---|---|---|---|
| 1 | `actor` → `Sendable` struct + concurrent queue, `perform`-хелпер, sync-реализации приватны | `Services/FastFolderBookmarkService.swift` | P0 |
| 2 | `statuses`/`refreshingIDs`, `attempts`/`tasks`/`watchdogs`, новый `refresh`/`finish`/`load`, удаление `withTimeout`/`FolderRefreshOutcome`/`FastFolderRefreshError`/`unavailableFolderIDs`/`unavailableCount` | `ViewModels/FastFolderStore.swift` | P0 |
| 3 | Снять глобальный disable и оверлей «Refreshing…», per-item индикатор | `Views/FastFolderView.swift`, `Views/FastFolderItemView.swift` | P0 |
| 4 | Три состояния item + retry, передача `availability` | `Views/FastFolderSettingsItemView.swift`, `Views/FastFolderSettingsView.swift` | P0 |
| 5 | `FinderPresenter` + `FinderPresenting`, удаление `openInNewFinderWindow` из bookmark-протокола | `Services/FinderPresenter.swift` (новый), `Services/FastFolderBookmarkService.swift` | P1 |
| 6 | `FolderPicker` + `FolderPicking`, AppKit уходит из вью, асинхронный `begin` | `Services/FolderPicker.swift` (новый), `Views/FastFolderSettingsView.swift` | P1 |
| 7 | Preview-support под `#if DEBUG`, delay, фейки finder/picker; починить `HomeUI` preview | `Views/FastFolderPreviewSupport.swift`, `UIPresets/HomeUI.swift` | P1 |
| 8 | Дедуп недоступных папок (path + name fallback) | `ViewModels/FastFolderStore.swift` | P1 |
| 9 | `FastFolderMetrics`, починить обрезку 96 vs 80 | `Views/FastFolderMetrics.swift` (новый), `FastFolderView`, `FastFolderSettingsView` | P2 |
| 10 | `FinderTagColor.color` → отдельный файл | `Views/FinderTagColor+SwiftUI.swift` (новый) | P2 |
| 11 | Порядок модификаторов `nonisolated private static` | store, service | P2 |
| 12 | Явный `Sendable`: `FastFolder`, `FastFolderAddOutcome`, `FastFolderAvailability`, `FastFolderStatus`, `FinderTagColor` | `Models/FastFolder.swift`, store | P2 |
| 13 | Убрать избыточный `@MainActor` с реализаций `FastFolderStorage` (дефолтная изоляция уже MainActor) | `Services/FastFolderStorage.swift` | P2 |
| 14 | Нейминг замыканий: `onOpen` / `onRetry` / `onRemove` | item-вью | P2 |
| 15 | Мёртвый код: закомментированный `.contentShape` (восстановить как активный `RoundedRectangle(cornerRadius: 18)`) | `Views/FastFolderItemView.swift` | P2 |
| 16 | Per-folder логи с длительностью, вместо агрегированной строки | `ViewModels/FastFolderStore.swift` | P2 |

`snapshot(of:)` через `guard let` — часть правки #1.

---

## 11. Файлы

| Файл | Что меняется |
|---|---|
| `Services/FastFolderBookmarkService.swift` | `actor` → `Sendable` struct + concurrent queue; `perform`; удаление `openInNewFinderWindow`; `guard let` в `snapshot` |
| `Services/FinderPresenter.swift` | **новый**: `@MainActor` protocol + реализация, `NSWorkspace` |
| `Services/FolderPicker.swift` | **новый**: `@MainActor` protocol + `NSOpenPanel` через `begin` |
| `Services/FastFolderStorage.swift` | убрать избыточный `@MainActor` с реализаций |
| `Models/FastFolder.swift` | явный `Sendable` у модели и `FinderTagColor` |
| `ViewModels/FastFolderStore.swift` | новое состояние и refresh (§6), finder/picker в `init`, дедуп, логи, удаление мёртвого API |
| `Views/FastFolderView.swift` | снять disable и оверлей, per-item индикатор, `.task`, метрики |
| `Views/FastFolderItemView.swift` | `isRefreshing`, `onOpen`, индикатор по центру, `contentShape`, `FinderTagColor.color` уходит |
| `Views/FinderTagColor+SwiftUI.swift` | **новый**: `FinderTagColor.color` |
| `Views/FastFolderMetrics.swift` | **новый**: единые метрики полки и настроек |
| `Views/FastFolderSettingsView.swift` | `.task`, picker через store, передача `availability`, метрики |
| `Views/FastFolderSettingsItemView.swift` | три состояния, retry, `onRemove`, индикатор, без текстов |
| `Views/FastFolderPreviewSupport.swift` | `#if DEBUG`, delay, фейки finder/picker |
| `UIPresets/HomeUI.swift` | рабочий `#Preview` с environment |
| `App/AppContainer.swift` | сборка `FinderPresenter`/`FolderPicker` и передача в store |

`PanelController`, `AppDelegate`, `RootView` в рамках этой работы не меняются (кроме вопроса §15).

---

## 12. Порядок реализации

Приложение собирается после каждого шага.

1. **Сервис.** `actor` → `Sendable` struct + concurrent queue, `perform`, `guard let` в `snapshot`. Сборка + ручная проверка, что папки открываются и читаются как раньше.
2. **Изоляция.** `FinderPresenting` + `FinderPresenter`, удаление `openInNewFinderWindow` из bookmark-протокола, `FinderPresenter` в store (`open`). Сборка.
3. **Store (ядро).** `statuses`, `refreshingIDs`, `attempts`, `tasks`, `watchdogs`; `refresh()`/`refresh(folderID:)`/`finish`/`load`; удаление `withTimeout`, `FolderRefreshOutcome`, `FastFolderRefreshError`, `unavailableFolderIDs`, `unavailableCount`; правки `addFolders`/`open`/`remove*`. Вью временно компилируются после замены `await store.refresh()` на `store.refresh()`.
4. **Полка.** Убрать глобальный disable и оверлей «Refreshing…», per-item индикатор, `.task`, плейсхолдеры по новым правилам.
5. **Настройки.** `availability` в item, три состояния, retry, `.task`, спиннер в тулбаре.
6. **Picker.** `FolderPicking` + `FolderPicker`, `addFoldersViaPicker()` в store, вью вызывает только действие; `AppContainer` собирает новые зависимости.
7. **Preview.** `#if DEBUG`, delay, фейки, починить `HomeUI`.
8. **Дедуп и полировка.** Fallback по имени, метрики, `FinderTagColor+SwiftUI`, порядок модификаторов, `Sendable`, `@MainActor` на storage, `onOpen`/`onRetry`, `contentShape`, per-folder логи.
9. **Проверка** по §14.

---

## 13. Риски

| Риск | Решение |
|---|---|
| Каждый зависший том держит поток очереди | папок ≤ 8; при росте лимита — `OperationQueue(maxConcurrentOperationCount:)` вместо `DispatchQueue` |
| Поздний результат после таймаута перезапишет состояние | `token` в `attempts`; проверка в `finish` |
| Задача-«сирота» продолжает работать после таймаута | осознанно: результат отбрасывается, завершение логируется на debug-уровне |
| `Task {}` внутри `@MainActor` store | тело задачи только ждёт; блокирующая работа — в сервисной очереди |
| Дубли refresh при частых `onAppear` | guard по `attempts[folderID]` — уже проверяемая папка пропускается, остальные проверяются |
| Retry недоступной папки «всплывает» на полку | видимость считается по `statuses`, `.refreshing` её не меняет (§4 п.3) |
| Сохранение на каждую папку | ≤ 8 маленьких JSON; выигрыш — данные не теряются из-за зависшего тома |
| Наблюдаемость `statuses`/`refreshingIDs` | обычные `@Observable`-свойства, инвалидация остаётся гранулярной |
| `NSOpenPanel.begin` в панельном окне без активного приложения | `NSApp.activate` перед `begin`; fallback — `runModal()` внутри picker'а |
| `FinderPresenter` вызывается не с main | тип `@MainActor`, вызов из `@MainActor` store — компилятор проверяет |
| Смена метрик ломает вёрстку панели | `shelfHeight` вычисляется из `itemHeight`; проверить пресеты 150 pt |
| Preview-support стал `#if DEBUG` и «пропал» из релиза | это цель: фейки и данные не должны попадать в биндинг; проверить Release-сборку |

---

## 14. Проверка

### 14.1 Сборка

```bash
xcodebuild -project Panel.xcodeproj -scheme Panel -destination 'platform=macOS' build
```

Дополнительно — Release-сборка после шага 7 (preview-support под `#if DEBUG`).

### 14.2 Ручные сценарии

1. 5 локальных папок + 1 на недоступном SMB: 5 появляются сразу, шестая скрывается через ~10 с; полка кликабельна всё время.
2. Все локальные: появляются почти одновременно, без «мигания» недоступности.
3. Сетевой том вернулся: следующий refresh возвращает папку на полку.
4. Удалить папку, пока она в `.refreshing`: нет фантомных id, нет падения, `isRefreshing` корректно сбрасывается.
5. Home → fastfolder → settings: уже проверяемые папки не перезапускаются, остальные проверяются.
6. Первый запуск: сохранённые папки видны сразу, затем обновляются.
7. Настройки: retry недоступной папки работает, удаление активно; спиннер только у проверяемой папки.
8. Refresh одной папки сохраняется в `UserDefaults`, даже если другая всё ещё висит.
9. Индикация: у каждой проверяемой папки спиннер по центру иконки; текстов состояния нет ни на полке, ни в настройках.
10. Добавить ту же папку, что уже есть и недоступна: второй раз не добавляется.
11. Добавление папок: диалог не блокирует панель, после выбора папки появляются сразу доступными.
12. Preview: `HomeUI`, `FastFolderUI` (3 варианта), `SettingsUI` открываются без падений, показывают локальные данные.

### 14.3 Grep-проверки

```bash
# 1. текстов про загрузку в UI быть не должно
grep -rn "Refreshing\|Preparing\|Loading\|Checking" Panel/Features/FastFolder/Views

# 2. индикатор загрузки — только per-item + тулбар настроек
grep -rn "ProgressView" Panel/Features/FastFolder/Views

# 3. синглтоны: только системный NSWorkspace в FinderPresenter
grep -rn "\.shared" Panel/Features/FastFolder

# 4. AppKit во вью отсутствует
grep -rn "NSOpenPanel\|NSApp\." Panel/Features/FastFolder/Views

# 5. мёртвый API удалён
grep -rn "unavailableFolderIDs\|unavailableCount\|FolderRefreshOutcome\|withTimeout\|FastFolderRefreshError" Panel/Features/FastFolder

# 6. глобальная блокировка полки снята
grep -rn "disabled(store.isRefreshing)" Panel/Features/FastFolder/Views
```

### 14.4 Критерии готовности

- refresh не блокирует UI и завершается по папке независимо; недоступный том даёт `.unavailable` за ~10 с;
- полка интерактивна во время любой проверки; пер-папочный статус меняется сразу;
- удаление и повторный refresh не оставляют фантомных id и «залипшего» `isRefreshing`;
- `.shared` в фиче — только `NSWorkspace` в `FinderPresenter`;
- `NSOpenPanel`/`NSApp` во вью отсутствуют;
- preview-support под `#if DEBUG`, все `#Preview` фичи собираются на локальных инстансах;
- `unavailableCount`, `withTimeout`, `FolderRefreshOutcome`, `FastFolderRefreshError` удалены;
- сборка без предупреждений о concurrency;
- в UI нет текстов про загрузку;
- per-folder логи позволяют увидеть независимость проверок.

---

## 15. Вне объёма и открытые вопросы

Вне объёма этой работы:

- параллелизация `addFolders` (сейчас последовательный цикл по URL);
- FSEvents / live-обновление статуса папки;
- таймаут на `open(_:)` (при необходимости переиспользует тот же механизм попыток);
- переименование `FastFolderBookmarkServiceProtocol` (общая конвенция проекта);
- `RootView`/`AirDropUI`/`BarView`/`NavigationRowView`, создающие `AppContainer()` в preview (нарушение §4, но не в периметре FastFolder).

Открытый вопрос (требует продуктового решения, код не меняем до ответа):

- `UIPresets/HomeUI.swift` рендерит `FastFolderView`, то есть полка показывается и в `.home`, и в `.fastfolder`. Похоже на недоделку: нужно решить, остаётся ли полка на home или home получает отдельный контент.
