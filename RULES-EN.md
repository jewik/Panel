# RULES.md — Architecture Rules for a Small/Medium Swift Application

> Universal rules derived from the experience of refactoring a SwiftUI + system-services
> project (macOS). Applicable to any Swift project of similar complexity (10–20 services,
> a single Composition Root, SwiftUI UI). Goal: explicit dependencies, compiler-enforced
> contracts, and no hidden global state.
>
> Normative language: **MUST** / **MUST NOT** / **SHALL** are strict requirements,
> **SHOULD** is a strong recommendation, **MAY** is an allowed option.

---

## 1. No Service Locator in Application Code

- `X.shared` inside the body of a view or service is **prohibited**, except for wrappers of
  **system** frameworks that hold no domain state (see §8).
- Any access via `static let shared` inside a method body is a hidden dependency: it is not
  visible in the signature, cannot be substituted in tests, and creates an implicit
  initialization order. Code SHALL NOT rely on such access.
- Simple review rule: if a type can be instantiated a second time, it MUST NOT reach into
  `.shared` of other application types.

## 2. The Single Composition Root

- The dependency container MUST be created **explicitly** at the entry point
  (`AppDelegate.applicationDidFinishLaunching`, `@main App.init`), not lazily via
  `static let shared` on first access.
- The container SHALL build the entire service graph via **constructor injection**: every
  service receives its dependencies through `init(...)` with all parameters; fields are `let`.
- The initialization order is known only to the root. Services MUST NOT "finish
  initializing" when first touched by someone else's code.
- The container has one explicit lifecycle: `start()` launches all listeners/timers **after**
  the graph is fully built; `stop()` (if needed) is the single point of shutdown.

## 3. UI Injection: Environment, Not Globals

- The root view receives dependencies from the Composition Root and distributes them
  downward via `.environment(...)` — the canonical path for `@Observable` types in modern
  SwiftUI.
- Nested views MUST read dependencies via `@Environment(Type.self)`, never via global access.
- Narrow local parameters (metrics, scale) MAY be passed via `init` directly — not everything
  is required to live in the environment.
- If a view reaches into state directly (`container.panelState.foo.toggle()`), bypassing the
  controller or an action method, that is an encapsulation violation. Mutations SHALL go
  through a controller method or an action.

## 4. Protocols Are Meaningful Only With Substitution

- Protocols for services (`XServiceProtocol`) exist to be substituted in tests and previews.
  If the only way to obtain an implementation is `.shared`, the protocol is decoration.
- Every `#Preview` MUST build on local instances (its own container, dummy stores). A preview
  that creates the real container is a DI red flag: it reads/writes UserDefaults, bookmarks,
  live state.

## 5. Layers and Dependency Direction

```
App (entry point, Composition Root)
  ↓
Panel/Shell (root views, state + controller)
  ↓
Features (feature = Model/Service + ViewModel + View)
  ↓
Platform (thin wrappers over system APIs: IOBluetooth, CoreAudio, EventTap, …)
```

- Dependencies point strictly **downward**: UI → ViewModel → Service → Platform.
- Services and stores MUST NOT know about the UI layer. A service MUST NEVER call
  `controller.show...` or reference view types. Instead of "perform an action in the UI",
  the service **publishes an event**, and the decision of "what to do" is made by a
  subscriber in the App layer. This breaks the "service → UI → service" cycles.
- A feature is a vertical slice: the Service owns a system API, the ViewModel owns observable
  state, the View only reads state and dispatches actions.

## 6. Events: Typed Streams Instead of String-based Notifications

- Application-own events MUST be typed `AsyncStream<Event>` (or a callback protocol with
  multiple slots). `Notification.Name` strings and `userInfo` dictionaries between
  application modules are **prohibited**: they forfeit compile-time checks.
- A single callback slot (`var onEvent: ((E) -> Void)?`) does not scale to multiple
  subscribers. Once a second listener appears, migrate to a stream / multi-slot approach.
- `NotificationCenter` remains legitimate **only for system** events
  (`DistributedNotificationCenter`, `NSWorkspace`, `NSApplication`) and SHALL live inside
  the Platform layer without leaking into clients.
- Stream termination is the natural cancellation mechanism; a subscriber's `deinit` MUST NOT
  stop a shared service (see §7).

## 7. Lifecycle Ownership

- The owner of a service is the Composition Root, not its subscribers. The pattern
  `deinit { SomeService.shared.stop() }` is **prohibited**: the last subscriber MUST NOT
  shut the service down for everyone else.
- If a service is needed for as long as the container lives, the container creates and
  starts it.

## 8. What Is Allowed to Remain a Singleton

- Wrappers of **system** frameworks that are single by nature and hold no domain state:
  a logger, a wrapper over a private windowing framework, `NSWorkspace.shared`,
  `NotificationCenter.default` (for system events), `UserDefaults.standard`.
- Criterion: `static let shared` is acceptable **only** where no application state exists.
  Anything holding domain state (stores, view models, notification queues, device managers)
  MUST be injected, even if there is factually a single instance. "Being one" is a matter of
  ownership (a single instance inside the container), not of static access.

## 9. The Actor Contract Lives in the Signature, Not in Comments

- Anything that touches UI/panel state: `@MainActor final class`. If a service publishes
  state read by the UI, it MUST be `@MainActor`.
- Background work (EventTap handling, CoreAudio callbacks, IOBluetooth) belongs in its own
  `actor` or on a queue **inside** the Platform wrapper; data crosses outward already on the
  main context, via `AsyncStream`/`continuation`.
- `DispatchQueue.main.async` as a "rescue" from races is not a contract. If safety relies on
  an internal `performOnMain` call instead of an actor annotation, the contract is unprotected
  and invisible in the signature. Move isolation into the type.
- `@MainActor` state MUST NOT be mutated from background queues: an event arriving from a
  background queue is delivered to a `@MainActor` handler through a stream/continuation.

## 10. Observable UI State

- UI state lives in an `@Observable` ViewModel/Store. A feature MUST NOT mirror it into local
  `@State` copies — it reads directly from the store. Duplicated icons/caches across several
  views fed from one store signal that the cache API belongs in the store itself.
- `@ObservationIgnored` is for caches and service fields that do not participate in UI
  invalidation.
- New types use `@Observable` (Observation). Mixing with the legacy
  `ObservableObject`/`@EnvironmentObject` in new code is **prohibited**.
- `@Environment` injection of `@Observable` gives granular invalidation: a view re-renders
  only from the properties it actually read.

## 11. Checklist for a New Feature

1. Feature = `Model/Service + ViewModel + View`; the Service owns a system API, the ViewModel
   owns observable state, the View only reads and dispatches actions.
2. Dependencies — only via `init(...)` or `.environment`. Grep test: method bodies contain no
   `AppContainer.shared` and no `X.shared`.
3. UI state lives in the feature's store/VM, not duplicated in `@State`.
4. Outgoing events — `AsyncStream`/callback protocol; no string-based Notifications, no
   `userInfo`.
5. Everything touching UI is `@MainActor`; background work is isolated in a platform wrapper.
6. `#Preview` builds on local instances with no side effects.
7. No `deinit`-based shutdown of shared services; the lifecycle belongs to the owner (the
   container).
8. State mutations go through the controller/an action, never a direct toggle from someone
   else's layer.

## 12. What Deliberately NOT to Do

- **Do not adopt third-party DI frameworks** (Swinject, Factory, Resolver, etc.) while the
  graph is a dozen-ish services: an explicit Composition Root is cheaper, more readable, and
  magic-free.
- **Do not outlaw system singletons for the sake of "principle"** — generalizing their
  ban mechanically is harmful.
- **Do not store UI state in NotificationCenter events** — state lives in typed
  `@Observable` objects; events are only "impulses".
- **Do not do a "big rewrite"**: migrate step by step — first bootstrap and environment in
  the view layer (a mechanical replacement of access points), then breaking the service
  cycles, then the platform finale. The application MUST build after every step.
- Final grep criterion of migration success:
  `grep -r "\.shared" Features/ Panel/` — empty, except for system OS singletons.
