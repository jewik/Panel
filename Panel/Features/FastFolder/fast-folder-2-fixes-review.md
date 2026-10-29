# FastFolder — ревью по RULES-EN.md и Swift 6 style

Дата: 29.10.2026
Объём: `Panel/Features/FastFolder/` + точки интеграции (`AppContainer`, `AppDelegate`, `UIPresets/*`, `RootView`).
Сборка: `xcodebuild -scheme Panel -destination 'platform=macOS' build` → **BUILD SUCCEEDED**, concurrency-предупреждений нет.

## Итог

Архитектурно фича в целом соответствует RULES: есть Composition Root, DI через `init`, `@Observable` store, `@Environment` во вью, сервис — `actor`, нет string-based нотификаций и `deinit`-остановок сервисов.

Найдено:

- 3 нарушения правил (§9, §5, §4/§11.6);
- 2 реальные проблемы поведения (таймаут не ограничивает время; устаревшие `unavailableFolderIDs`);
- 1 проблема дедупа при добавлении;
- набор замечаний по Swift 6 / стилю.

---

## 1. Соответствие RULES

| § | Правило | Статус |
|---|---|---|
| 1 | Нет Service Locator | OK — `.shared` только `NSWorkspace.shared` в platform-слое (`Services/FastFolderBookmarkService.swift:107,110`) |
| 2 | Единый Composition Root | OK — `AppContainer` создаётся явно в `AppDelegate`, граф собирается конструктором (`App/AppContainer.swift:23-39`) |
| 3 | UI через Environment | OK — `@Environment(FastFolderStore.self)`, мутации только через методы store/контроллера |
| 4 | Протоколы + локальные preview | ЧАСТИЧНО — протоколы имеют фейки, но preview-код не под `#if DEBUG`, preview `HomeUI` сломан |
| 5 | Слои вниз | ЧАСТИЧНО — `NSOpenPanel` + `NSApp.activate` живут в View |
| 6 | Типизированные события | OK — приложение-событий нет, состояние наблюдаемое |
| 7 | Lifecycle у владельца | OK — нет `deinit`-shutdown |
| 8 | Синглтоны | OK — доменного состояния в синглтонах нет |
| 9 | Актор в сигнатуре | НАРУШЕНО — `MainActor.run` спрятан в теле actor-метода |
| 10 | Observable-состояние | OK — `@Observable`, `@ObservationIgnored` только на сервисах, без `ObservableObject` |
| 11 | Чеклист фичи | ЧАСТИЧНО — п.6 (preview) и п.1 (вью не должна владеть AppKit-презентером) |

---

## 2. Нарушения правил

### 2.1 §9 — изоляция не видна в сигнатуре

`Services/FastFolderBookmarkService.swift:98-113`

```swift
func openInNewFinderWindow(_ url: URL) async {
    await MainActor.run { ... NSWorkspace.shared ... }
}
```

Протокол обещает «actor, всё off-main», но внутри — прыжок на MainActor. Это ровно тот «rescue», который §9 запрещает: контракт спрятан в теле, а не в сигнатуре.

Варианты исправления:

1. вынести открытие Finder в отдельный `@MainActor` тип (`FinderPresenter`) и инжектить его в store рядом с bookmark-сервисом;
2. объявить требование `@MainActor` в протоколе и реализовать его вне actor.

Вариант 1 предпочтителен: actor остаётся чистым platform-слоем без UI-обязанностей.

### 2.2 §5 — AppKit-презентер внутри View

`Views/FastFolderSettingsView.swift:119-143`

`NSOpenPanel()`, `runModal()`, `NSApp.activate(ignoringOtherApps:)` — это работа Platform/контроллера, а вью по §11.1 «only reads state and dispatches actions». Дополнительно синхронный `runModal()` внутри вьюхи блокирует поток на всё время диалога.

Правильно: `FolderPicker` (protocol + `@MainActor` реализация) → store/контроллер возвращает `[URL]`, вью только вызывает действие. Тогда и preview настроек не будет тянуть AppKit-модалку.

### 2.3 §4 / §11.6 — preview

- `Views/FastFolderPreviewSupport.swift` целиком компилируется в релизный бинарник: `InMemoryFastFolderStorage`, `PreviewBookmarkService`, `PreviewFastFolder`, `makePreviewFastFolderStore`. Обернуть в `#if DEBUG` (и/или вынести в `Views/Preview/`).
- `UIPresets/HomeUI.swift:21` — `#Preview` без `.environment(...)`: `FastFolderView` требует `FastFolderStore` и `PanelController` → preview упадёт.
- `Panel/Views/RootView.swift:151-156` — создаёт `AppContainer()` дважды (реальные `UserDefaults`, живые сервисы). Нарушение §4, но вне периметра фичи.

---

## 3. Проблемы поведения

### 3.1 Таймаут не ограничивает время (высокий приоритет)

`ViewModels/FastFolderStore.swift:37-59` и `:255-283`

`withThrowingTaskGroup` при выходе из scope **дожидается всех** дочерних задач. `cancelAll()` не прерывает блокирующий `getxattr` / резолв bookmark на сетевом томе, поэтому `withTimeout` вернёт `.timedOut` только после того, как «зависший» вызов сам завершится.

Следствие: 15-секундный таймаут для блокирующих syscall'ов фактически не работает. UI не фризится (вызов на акторе), но `isRefreshing` висит, и полка остаётся disabled — то есть `fixes-1.md` закрыт не полностью.

Нужен действительно отвязываемый путь: unstructured `Task` / `DispatchQueue.global` + continuation, где «проигравшую» задачу не дожидаются (её позднее завершение только логируется).

### 3.2 `unavailableFolderIDs` может содержать id удалённых папок

`ViewModels/FastFolderStore.swift:137-143`, `:208-218`

Если во время `refresh()` пользователь удаляет папку, а её child-task вернул `.failed`, в конце `unavailableFolderIDs = unavailableIDs` вернёт id уже несуществующей папки → раздутый `unavailableCount`.

Исправление: перед присваиванием пересечь с актуальным списком:

```swift
unavailableIDs.formIntersection(folders.map(\.id))
```

### 3.3 Дедуп не видит недоступные папки

`ViewModels/FastFolderStore.swift:159-163`

`try? await resolve(...)` — если существующая папка недоступна, её путь не попадает в `knownPaths`, и ту же папку можно добавить второй раз. Нужен fallback: при неудачном резолве сравнивать хотя бы сохранённый `name` (или помечать запись как «путь неизвестен» и не считать её отсутствующей).

### 3.4 Мёртвый и сомнительный API

- `unavailableCount` (`ViewModels/FastFolderStore.swift:86`) нигде не используется.
- `UIPresets/HomeUI.swift:12` рендерит `FastFolderView`, т.е. полка показывается и в `.home`, и в `.fastfolder` — похоже на недоделку, а не на замысел.

---

## 4. Swift 6 / стиль

Формально проект **не в Swift 6 language mode**: `SWIFT_VERSION = 5.0`, но включены `SWIFT_APPROACHABLE_CONCURRENCY = YES` и `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. «Swift 6 корректность» здесь держится на дефолтной изоляции — это надо учитывать при ревью и не рассчитывать на ошибки компилятора там, где изоляция задана неявно.

1. **Несогласованный порядок модификаторов** в одном файле: `nonisolated private static let` (`FastFolderStore.swift:69`) vs `private nonisolated static func` (`:255`).
2. **Неявный `Sendable`**: `FastFolder` и `FastFolderAddOutcome` пересекают границу nonisolated-кода (`refreshFolder`), но `Sendable` не объявлен — работает за счёт неявного вывода. `FolderSnapshot` объявлен явно; для консистентности объявить и модель.
3. **Избыточный `@MainActor`** на `UserDefaultsFastFolderStorage` и `InMemoryFastFolderStorage`: при `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` он ничего не добавляет. Либо явно везде, либо нигде — сейчас непоследовательно.
4. **`.onAppear { Task { … } }` вместо `.task`** (`FastFolderView.swift:44-48`, `FastFolderSettingsView.swift:25-29`): задача не отменяется при исчезновении вью, а guard `isRefreshing` не коалесцирует повторный refresh, а молча его глотает. `.task` идиоматичнее и даёт отмену.
5. **Дублирование метрик вёрстки**: `itemWidth = 76`, `shelfHeight = 100`, `horizontalPadding = 10` в `FastFolderView` против захардкоженных `76×96` в `FastFolderItemView.swift:49-51` и `86×84 / 70×54 / 62×54` в `FastFolderSettingsItemView`. При этом 96pt-элемент кладётся в скролл высотой `100 - 20 = 80` → контент обрезается. По §3 узкие параметры (metrics) MAY передаваться через `init` — вынести в один `FastFolderMetrics`.
6. **`FinderTagColor.color` объявлен в `FastFolderItemView.swift:10-23`**, но используется и в `FastFolderSettingsItemView` — расширение живёт в чужом файле. Место ему — `FinderTagColor+SwiftUI.swift` в `Views/`.
7. **`withTimeout` — глобальная generic-функция в файле ViewModel**. В проекте есть `Panel/Extensions/` (`extension+Animation.swift`) — туда и просится: переиспользуемо, тестируемо, без коллизий имён.
8. **Мёртвый код**: закомментированный `.contentShape(...)` в `FastFolderItemView.swift:53`.
9. **Нейминг замыканий**: `FastFolderItemView(folder:action:)` — по API guidelines лучше `onOpen`/`onRemove` (у settings-item уже `onRemove`, то есть внутри фичи стиль разъехался).
10. **`FastFolderBookmarkServiceProtocol`** — суффикс `Protocol` неидиоматичен (лучше `FastFolderBookmarking`), но это общая конвенция проекта, поэтому скорее заметка, чем замечание.
11. **`snapshot(of:)`** (`FastFolderBookmarkService.swift:83-95`): `if let … { return }` + fallback `return` читается лучше через `guard let … else { return fallback }`.

---

## 5. План правок по приоритету

1. `withTimeout` — сделать реально ограничивающим по времени (см. 3.1); иначе `fixes-1.md` не закрыт.
2. `openInNewFinderWindow` — вынести MainActor-часть из actor, изоляцию показать в сигнатуре (см. 2.1).
3. `NSOpenPanel` — из вью в picker-сервис (см. 2.2).
4. `#if DEBUG` вокруг preview-support + починить preview `HomeUI` (см. 2.3).
5. Фильтрация `unavailableFolderIDs` по актуальному списку папок (см. 3.2).
6. Дедуп при добавлении недоступных папок (см. 3.3).
7. Метрики вёрстки — в одно место, починить обрезку 96 vs 80 (см. 4.5).
8. Косметика: `.task`, порядок модификаторов, явный `Sendable`, мёртвый код, `unavailableCount`.

## 6. Критерии готовности

- `grep -rn "\.shared" Panel/Features/FastFolder` → только `NSWorkspace.shared` (или ничего, если Finder вынесен в отдельный presenter).
- `grep -rn "NSOpenPanel\|NSApp\." Panel/Features/FastFolder/Views` → пусто.
- В `Views/FastFolderPreviewSupport.swift` весь код под `#if DEBUG`.
- Все `#Preview` фичи (включая `HomeUI`) собираются на локальных инстансах и не падают.
- Сборка без предупреждений о concurrency.
- Ручной сценарий из `fixes-1.md`: недоступный сетевой том → refresh завершается за ~15 с, полка снова активна, приложение не «залипает».
