# FastFolder — план реализации

Статус: план согласован в Plan mode. Реализация — после переключения на агент сборки.
Целевой путь копии: `Panel/Features/FastFolder/fast-folder-feature-plan.md` (записать после выхода из Plan mode).

## 1. Цель

Полка часто используемых папок в раскрытой панели (preset `.fastfolder`):

- по умолчанию полка пуста;
- папки добавляются/удаляются/обновляются в пресете `.settings`;
- каждая папка — кнопка `Image(systemName: "folder.fill")` с названием под иконкой;
- цвет иконки — цвет первого Finder-тега папки, `.cyan` если тегов нет;
- клик открывает папку в новом окне Finder;
- список сохраняется в `UserDefaults` через security-scoped bookmarks;
- при появлении полки и настроек выполняется refresh (существование, имя, теги, цвет).

## 2. Принятые решения

| # | Решение |
|---|---------|
| 1 | Цвет — из xattr `com.apple.metadata:_kMDItemUserTags` (`"Имя\nColorIndex"`), первый тег; fallback `.cyan` при отсутствии тегов, `ColorIndex == 0` или ошибке парсинга |
| 2 | Максимум 8 папок; при переполнении — горизонтальный скролл |
| 3 | Недоступная папка скрывается с полки, но остаётся в настройках приглушённой с возможностью удаления; молчаливого автоудаления нет |
| 4 | `UIPresets/SettingsUI.swift` — контейнер секций, `FastFolderSettingsView` лежит в `Features/FastFolder/Views/` |
| 5 | `NSOpenPanel` с `allowsMultipleSelection = true`, дедуп по разрешённому пути, лишние сверх лимита отбрасываются; drag-and-drop на полку не делаем |
| 6 | Порядок — порядок добавления, без реордера и сортировки |
| 7 | Пустая полка — плейсхолдер с кнопкой перехода в `.settings` |
| 8 | Ширина полки по содержимому (кап ~900), одна строка, скролл при переполнении |
| 9 | Слои: Model + BookmarkService (platform) + Storage (UserDefaults) + Store (VM) + Views |
| 10 | Refresh только `onAppear` полки/настроек + ручная кнопка; без FSEvents/таймеров |
| 11 | Ключ `fastFolders`, tolerant-decode (`decodeIfPresent` для `tags`/`tagColorIndex`) |
| 12 | План пишется в `/Users/ivan/.opencode/plan`, затем копируется в репозиторий |
| 13 | Настройки: горизонтальная лента чипов + тулбар `FastFolders n/8` / Refresh / Clear / Add, `600×150` |
| 14 | Clear all — с `confirmationDialog`, доступна только при непустом списке |
| 15 | Если все папки недоступны — плейсхолдер «Folders unavailable» + кнопка в настройки |
| 16 | На время `NSOpenPanel` — активация `NSApp` (временный пин не нужен: settings уже авто-пинится) |
| 17 | Протокол только для хранилища; preview — in-memory фейк, без реальных `UserDefaults` и файловой системы |
| 18 | Подписи UI — английский |
| 19 | После открытия папки панель остаётся открытой |
| 20 | Авто-пин: `effectivePin = userPin \|\| autoPin`, `autoPin = panelMode == .expanded && expandedPreset == .settings` |
| 21 | Клик по пину в settings снимает авто-пин (override), `userPin` не меняется; при выходе из settings override сбрасывается → возвращается состояние до входа |
| 22 | Из settings нельзя выйти уходом курсора, пока авто-пин активен; выход — кнопки пресетов или снятие авто-пина пином |
| 23 | Авто-пин визуально не отличается от обычного |

## 3. Файловая структура

```
Panel/Features/FastFolder/
├── Models/
│   └── FastFolder.swift              # FastFolder, FinderTagColor
├── Services/
│   ├── FastFolderBookmarkService.swift   # platform: bookmarks, теги, xattr, открытие
│   └── FastFolderStorage.swift           # протокол + UserDefaults-реализация
├── ViewModels/
│   └── FastFolderStore.swift             # @Observable состояние и действия
└── Views/
    ├── FastFolderView.swift              # полка (preset)
    ├── FastFolderItemView.swift          # иконка + имя
    ├── FastFolderSettingsView.swift      # секция настроек
    ├── FastFolderSettingsItemView.swift  # чип папки с ×
    └── FastFolderPreviewSupport.swift    # in-memory storage + тестовые папки для #Preview
```

Изменяемые файлы:

- `Panel/UIPresets/FastFolderUI.swift` — обёртка полки;
- `Panel/UIPresets/SettingsUI.swift` — контейнер секций настроек;
- `Panel/App/AppContainer.swift` — сборка `fastFolderStore`;
- `Panel/App/AppDelegate.swift` — `.environment(container.fastFolderStore)`;
- `Panel/Panel/State/PanelState.swift` — `isAutoPinSuppressed`;
- `Panel/Panel/Controllers/PanelController.swift` — авто-пин и сброс override;
- preview в `Panel/Views/RootView.swift`, `ExpandedContentView.swift`, `NavigationRowView.swift` — добавить store, если понадобится для компиляции.

`PBXFileSystemSynchronizedRootGroup` — правка `.pbxproj` не требуется.

## 4. Архитектура и DI

- `AppContainer` (Composition Root) создаёт:
  `UserDefaultsFastFolderStorage` → `FastFolderBookmarkService` → `FastFolderStore`.
- `FastFolderStore` инжектится в `RootView` через `.environment(...)` в `AppDelegate.makeHostingView()`.
- Views читают `@Environment(FastFolderStore.self)`, мутации — только через методы store.
- Никаких `.shared` внутри тел методов; `NSWorkspace.shared` / `UserDefaults.standard` живут только внутри platform/storage слоя.
- Все новые типы `@MainActor` (в проекте `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), UI-состояние — `@Observable`.
- `FastFolderStore` — единственный источник истины; views не дублируют `folders` в `@State`.

## 5. Модель

```swift
struct FastFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var bookmark: Data
    var tags: [String]          // decodeIfPresent, default []
    var tagColorIndex: Int      // decodeIfPresent, default 0
}

enum FinderTagColor: Int {
    case none = 0, gray = 1, green = 2, purple = 3, blue = 4, yellow = 5, red = 6, orange = 7
}
```

- `FinderTagColor` без `import SwiftUI`; маппинг в `Color` — extension в слое Views:
  `gray→.gray, green→.green, purple→.purple, blue→.blue, yellow→.yellow, red→.red, orange→.orange`,
  `none` и неизвестные значения → `.cyan`.
- `id` стабилен между refresh (папку не пересоздаём).
- Доступность не персистится: runtime-состояние живёт в store.

## 6. Сервисы

### 6.1 `FastFolderBookmarkService` (platform)

`@MainActor final class`, без доменного состояния:

- `func makeBookmark(for url: URL) throws -> Data` — `.withSecurityScope`.
- `func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)` — резолв с `.withSecurityScope`.
- `func snapshot(of url: URL) throws -> FolderSnapshot` — под `startAccessingSecurityScopedResource()`/`defer`:
  - проверка `isDirectory`;
  - `URLResourceValues(forKeys: [.nameKey, .tagNamesKey])`;
  - чтение xattr `com.apple.metadata:_kMDItemUserTags` через `getxattr` + `PropertyListSerialization`;
  - `FolderSnapshot { name, tags, tagColorIndex }`; при неудаче xattr — `tags` из `tagNamesKey`, `tagColorIndex = 0`.
- `func openInNewFinderWindow(_ url: URL)` — `NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)`, fallback `NSWorkspace.shared.open(url)`; доступ под security scope.
- Все системные вызовы изолированы здесь; наружу — только значения.

### 6.2 `FastFolderStorage`

```swift
protocol FastFolderStorage {
    func load() -> [FastFolder]
    func save(_ folders: [FastFolder])
}
```

- `UserDefaultsFastFolderStorage`: ключ `fastFolders`, JSON-массив, `decodeIfPresent` для новых полей;
  ошибки — `Log.service.error(...)`, битые данные не затирают стор без сохранения.
- `InMemoryFastFolderStorage` — в `FastFolderPreviewSupport.swift`, используется только в `#Preview`.

## 7. `FastFolderStore` (VM)

```swift
@MainActor @Observable
final class FastFolderStore {
    static let maximumFolderCount = 8

    private(set) var folders: [FastFolder] = []
    private(set) var unavailableFolderIDs: Set<UUID> = []

    var canAddFolder: Bool
    var availableFolders: [FastFolder]      // для полки
    var unavailableCount: Int

    init(storage: FastFolderStorage, bookmarkService: FastFolderBookmarkService)

    func refresh()
    func addFolders(_ urls: [URL]) -> AddOutcome
    func removeFolder(id: FastFolder.ID)
    func removeAll()
    func open(_ folder: FastFolder)
}
```

Поведение:

- `refresh()`:
  1. для каждой папки — резолв bookmark;
  2. stale bookmark → пересоздать и запомнить необходимость save;
  3. папка не резолвится / не существует / не директория → `unavailableFolderIDs.insert(id)`, запись остаётся;
  4. иначе — `snapshot(of:)`: обновить `name`, `tags`, `tagColorIndex`, убрать из `unavailableFolderIDs`;
  5. `save()` только если что-то изменилось; логировать количество обновлённых/недоступных.
- `addFolders(_:)`:
  - отбрасывает лишние сверх лимита;
  - дедуп по `url.standardizedFileURL.path` против уже сохранённых (резолв их bookmarks) и внутри пакета;
  - создаёт bookmark + snapshot, добавляет, сохраняет;
  - возвращает `AddOutcome { added, skippedDuplicates, rejectedByLimit, failed }` для логов/тултипа.
- `removeFolder(id:)` / `removeAll()` — удаление из массива, чистка `unavailableFolderIDs`, save.
- `open(_:)` — резолв; если недоступна — ничего не делает (на полке такие скрыты); иначе `openInNewFinderWindow`.
- Никаких обращений к UI-слою; события наружу не нужны — состояние наблюдаемое.

## 8. UI

### 8.1 Полка — `FastFolderView` + `FastFolderItemView`

- `.onAppear { store.refresh() }`.
- Состояния:
  - `folders.isEmpty` → `folder.badge.plus` + «Add folders in Settings», кнопка `controller.showExpandedPreset(.settings)`;
  - `availableFolders.isEmpty && !folders.isEmpty` → «Folders unavailable» + та же кнопка;
  - иначе — `ScrollView(.horizontal)` с `HStack(spacing: 8)`.
- Ширина: `min(CGFloat(count) * 76 + CGFloat(count - 1) * 8 + 20, 900)`, высота 116.
- Элемент: `Button` → `VStack(spacing: 4) { Image(systemName: "folder.fill") (34pt, цвет тега); Text(name) (11pt semibold rounded, lineLimit 1, truncationMode .middle, width 76) }`, frame `76×96`, `.buttonStyle(.plain)`, hover: подъём на 3pt + лёгкая тень/подсветка, `.help(name)`.
- Имя видно всегда (не только на hover).
- `.accessibilityLabel(name)`, hint «Opens the folder in a new Finder window».

### 8.2 `UIPresets/FastFolderUI.swift`

```swift
struct FastFolderUI: View {
    var body: some View { FastFolderView() }
}
```

- `#Preview` — локальный `FastFolderStore` на `InMemoryFastFolderStorage` с 2–3 тестовыми папками; без `AppContainer()`, без реальных UserDefaults/файлов.

### 8.3 Настройки — `FastFolderSettingsView` (+ item)

- `.onAppear { store.refresh() }`, frame `600×150`.
- Шапка: `Text("FastFolders")`, счётчик `n/8`, `Spacer`, кнопки:
  - Refresh (`arrow.clockwise`, disabled при пустом списке);
  - Clear all (`trash`, disabled при пустом списке, `confirmationDialog`);
  - Add (`plus`, disabled при `!canAddFolder`).
- Add: `NSApp.activate(ignoringOtherApps: true)` → `NSOpenPanel` (`canChooseDirectories = true`, `canChooseFiles = false`, `allowsMultipleSelection = true`) → `store.addFolders(panel.urls)`.
- Список: `ScrollView(.horizontal)` с чипами: `folder.fill` цвета тега (54pt), имя (11pt, width 72), кнопка `xmark` в круге.
- Недоступная папка: `folder.badge.questionmark`, `opacity 0.4`, `.help("Folder is unavailable")`, кнопка удаления активна.
- Пусто: `Text("No folders added")` по центру.

### 8.4 `UIPresets/SettingsUI.swift`

- `VStack` с `FastFolderSettingsView()` (задел под будущие секции), сохранить `600×150` и стиль пресета.

## 9. Авто-пин настроек

`PanelState`:

```swift
var isPanelPinned: Bool = false        // ручной пин (существующее поле)
var isAutoPinSuppressed: Bool = false  // сессионный override, не персистится
```

`PanelController`:

- `private var autoPinActive: Bool { panelState.panelMode == .expanded && panelState.expandedPreset == .settings && !panelState.isAutoPinSuppressed }`
- `func isPanelPinned() -> Bool { panelState.isPanelPinned || autoPinActive }`
- `func togglePinned()`:
  - если `autoPinActive` → `panelState.isAutoPinSuppressed = true` (ручной флаг не трогаем);
  - иначе → `panelState.isPanelPinned.toggle()`.
- `func showExpandedPreset(_ preset:)`: если `preset != .settings` → `panelState.isAutoPinSuppressed = false`; далее как сейчас.
- `showCollapsedPreset()` не меняется: проверяет эффективный пин, поэтому в settings панель не схлопывается по hover.
- `pinPanel()` / `unpinPanel()` продолжают управлять только ручным флагом.
- Итог: вход в settings пинит; выход через другой пресет возвращает ровно то состояние `userPin`, что было до входа; ручной клик по пину в settings отпускает авто-пин до конца визита в настройки (и hover-out снова работает, если панель не была запинена вручную).
- `NavigationRowView` не меняется — использует `isPanelPinned()` / `togglePinned()`.

## 10. Цвета Finder-тегов

| ColorIndex | Значение | SwiftUI |
|---|---|---|
| 1 | Gray | `.gray` |
| 2 | Green | `.green` |
| 3 | Purple | `.purple` |
| 4 | Blue | `.blue` |
| 5 | Yellow | `.yellow` |
| 6 | Red | `.red` |
| 7 | Orange | `.orange` |
| 0 / неизвестно | без цвета | `.cyan` (default) |

Порядок тегов берётся из xattr-массива (порядок Finder); при fallback на `tagNamesKey` цвет = `.cyan`.

## 11. Preview

- Каждый `#Preview` собирает локальный `FastFolderStore` на `InMemoryFastFolderStorage`.
- Сценарии: пустая полка, 3 папки с разными цветами, все недоступны, настройки с 3 папками и с недоступной.
- Никаких `AppContainer()`, `UserDefaults.standard`, `NSOpenPanel` и обращений к диску в preview.

## 12. Ошибки и логирование

- `Log.service` — bookmark/resolve/xattr/UserDefaults ошибки, количество обновлённых и недоступных папок.
- `Log.ui` — добавление/удаление, открытие папки, срабатывание авто-пина (по желанию, debug-уровень).
- Битые записи в UserDefaults: `load()` возвращает `[]`, ошибка логируется, данные не перезаписываются до первого явного действия.

## 13. Порядок реализации

1. `FastFolder` + `FinderTagColor`, extension цвета в Views.
2. `FastFolderStorage` + `UserDefaultsFastFolderStorage`.
3. `FastFolderBookmarkService` (bookmarks, snapshot, xattr, open).
4. `FastFolderStore` (refresh/add/remove/open).
5. `AppContainer` + `AppDelegate` — сборка и инжект.
6. `FastFolderView` + `FastFolderItemView` + `FastFolderUI`.
7. `FastFolderSettingsView` + item + `SettingsUI`.
8. Авто-пин в `PanelState`/`PanelController`.
9. Preview support и `#Preview`.
10. Сборка и ручная проверка.

## 14. Проверка

- `xcodebuild -scheme Panel -destination 'platform=macOS' build` — без ошибок и предупреждений о concurrency.
- Ручные сценарии:
  1. чистый запуск → полка пустая, плейсхолдер ведёт в настройки;
  2. Add → несколько папок, дубликат не добавляется, 9-я отбрасывается;
  3. папка с тегом → цвет иконки совпадает с Finder; без тега → cyan;
  4. клик → новое окно Finder, панель остаётся открытой;
  5. удалить тег в Finder → refresh в настройках/переоткрытие полки меняет цвет на cyan;
  6. удалить папку в Finder → пропадает с полки, в настройках приглушена, удаляется вручную;
  7. перезапуск приложения → список сохранился, теги обновились при появлении;
  8. вход в settings → панель запинена; Home → пин вернулся к состоянию до входа; клик по пину в settings → hover-out схлопывает панель (если не была запинена вручную).
- `grep -r "\.shared" Panel/Features/FastFolder` — только `NSWorkspace.shared` внутри `FastFolderBookmarkService`.
- `grep -rn "UserDefaults" Panel/Features/FastFolder` — только `FastFolderStorage.swift`.

## 15. Вне объёма

- drag-and-drop папок на полку и файлов на иконку;
- реордер и сортировка;
- FSEvents / live-обновление тегов;
- контекстное меню, «Reveal in Finder», drag-and-drop из полки;
- локализация;
- тест-таргет и unit-тесты;
- настройки других фич в `SettingsUI`.
