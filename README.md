# WebScreenVCKit

`WebScreenVCKit` — SDK с готовым `WebScreenViewController` (UI + логика WebScreen), который подключается через адаптеры вашего приложения.

## Установка (SPM)

1. `File` -> `Add Package Dependencies...`
2. Укажите локальный путь или URL репозитория.
3. Выберите продукт `WebScreenVCKit`.

`Package.swift`: `/Users/artem/Documents/WebScreenVCKit/Package.swift`

## Быстрый старт

```swift
import WebScreenVCKit

// ВАЖНО:
// myURLPolicy / myRouting / myDeepLinkHandler / myStateStore / myPushService / myTokenProvider
// — это ВАШИ собственные объекты, которые вы создаете в приложении.

let configuration = WebScreenConfiguration(
    initialURL: URL(string: "https://example.com"),
    appType: "1",
    appID: "your_app_id",
    pushURLNotificationName: Notification.Name("didReceivePushURL")
)

let environment = WebScreenEnvironmentValues(
    urlPolicy: myURLPolicy,
    routing: myRouting,
    deepLinkHandler: myDeepLinkHandler,
    stateStore: myStateStore,
    pushService: myPushService,
    tokenProvider: myTokenProvider,
    capabilities: .init(
        pushFlowEnabled: true,
        debugTokensEnabled: false,
        deeplinkEnabled: true,
        urlEnrichmentEnabled: true
    ),
    webViewProcessPool: mySharedProcessPool
)

let vc = WebScreenViewController(configuration: configuration, environment: environment)
navigationController?.pushViewController(vc, animated: true)
```

## Минимальный Рабочий Пример (С Нуля)

```swift
import UIKit
import WebScreenVCKit

final class MyURLPolicy: WebScreenURLPolicy {
    func classify(_ url: URL) -> WebScreenURLDecision {
        guard let scheme = url.scheme?.lowercased() else { return .invalid }
        if scheme == "http" || scheme == "https" { return .internal }
        return .deeplink
    }

    func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

final class MyRouting: WebScreenRouting {
    weak var host: UIViewController?

    init(host: UIViewController) {
        self.host = host
    }

    func route(_ command: WebScreenRouteCommand) {
        switch command {
        case .featureApp:
            print("Agreement accepted")
        case .dismiss:
            host?.navigationController?.popViewController(animated: true)
        }
    }
}

final class MyDeepLinkHandler: WebScreenDeepLinkHandling {
    func handle(_ deeplink: String) {
        print("deeplink:", deeplink)
    }

    func executePending() {}
}

final class MyStateStore: WebScreenStateStore {
    var isAgreement: Bool = false
    var pushURL: String?
}

final class MyPushService: WebScreenPushService {
    func fetchStatus(completion: @escaping (WebScreenRemoteNotificationsStatus?) -> Void) {
        completion(.notDetermined)
    }

    func register(completion: @escaping (WebScreenRemoteNotificationsStatus?) -> Void) {
        completion(.allowed)
    }

    func unregister(completion: @escaping (WebScreenRemoteNotificationsStatus?) -> Void) {
        completion(.denied)
    }
}

final class MyTokenProvider: WebScreenTokenProvider {
    func fcmToken() -> String? { nil }
    func mindboxUUID(completion: @escaping (String) -> Void) { completion("") }
}
```

```swift
// В вашем ViewController:
let configuration = WebScreenConfiguration(
    initialURL: URL(string: "https://example.com"),
    appType: "1",
    appID: "123"
)

let environment = WebScreenEnvironmentValues(
    urlPolicy: MyURLPolicy(),
    routing: MyRouting(host: self),
    deepLinkHandler: MyDeepLinkHandler(),
    stateStore: MyStateStore(),
    pushService: MyPushService(),
    tokenProvider: MyTokenProvider(),
    capabilities: .init(
        pushFlowEnabled: true,
        debugTokensEnabled: false,
        deeplinkEnabled: true,
        urlEnrichmentEnabled: true
    ),
    webViewProcessPool: nil
)

let vc = WebScreenViewController(configuration: configuration, environment: environment)
navigationController?.pushViewController(vc, animated: true)
```

## Что Реализовать В Хост-Приложении

- `WebScreenURLPolicy` — классификация URL (`internal/external/deeplink/invalid`) и открытие внешних ссылок.
- `WebScreenRouting` — реакция на команды SDK (`featureApp`, `dismiss`).
- `WebScreenDeepLinkHandling` — прием и выполнение deeplink.
- `WebScreenStateStore` — состояние `isAgreement`, `pushURL`.
- `WebScreenPushService` — bridge для `fetch/register/unregister` пуш-статуса.
- `WebScreenTokenProvider` — `fcmToken` и `mindboxUUID`.

## Параметры `WebScreenEnvironmentValues`

Точная сигнатура и порядок:

```swift
WebScreenEnvironmentValues(
    urlPolicy: WebScreenURLPolicy? = nil,
    routing: WebScreenRouting? = nil,
    deepLinkHandler: WebScreenDeepLinkHandling? = nil,
    stateStore: WebScreenStateStore? = nil,
    pushService: WebScreenPushService? = nil,
    tokenProvider: WebScreenTokenProvider? = nil,
    capabilities: WebScreenCapabilities = .init(),
    webViewProcessPool: WKProcessPool? = nil
)
```

Любой параметр можно передать `nil`, если ветка не нужна.

## Важно: `WebScreenCapabilities`

```swift
public struct WebScreenCapabilities {
    public var pushFlowEnabled: Bool
    public var debugTokensEnabled: Bool
    public var deeplinkEnabled: Bool
    public var urlEnrichmentEnabled: Bool
}
```

Это feature-flags SDK. Они действительно влияют на поведение:

- `pushFlowEnabled`
Включает только внутреннюю push-ветку SDK (`fetchStatus/register/unregister`) после проверки контента страницы.
Если `false`: SDK не будет запрашивать/синхронизировать push-статус.
Важно: это не отключает пуши в приложении глобально.

- `debugTokensEnabled`
Показывает debug-alert с `Firebase token` и `Mindbox UUID`.
Если `false`: alert не показывается.

- `deeplinkEnabled`
Включает обработку deeplink внутри SDK (из URL и JS-сообщений).
Если `false`: deeplink-ветки в SDK не выполняются.

- `urlEnrichmentEnabled`
Включает добавление query-параметров к URL (`app_type`, `app_id`, `a_ssid`, `mb_uuid`).
Если `false`: URL открывается без обогащения.

Значения по умолчанию:
- `pushFlowEnabled = true`
- `debugTokensEnabled = false`
- `deeplinkEnabled = true`
- `urlEnrichmentEnabled = true`

## `pushURLNotificationName` — Когда Нужен

`pushURLNotificationName` нужен, если вы хотите, чтобы открытый WebScreen реагировал на внешний push URL.

Механика:
1. Хост-приложение кладет ссылку в `stateStore.pushURL`.
2. Хост-приложение отправляет `NotificationCenter` событие.
3. SDK получает событие, читает `pushURL`, открывает URL в WebView, очищает `pushURL`.

Пример:

```swift
stateStore.pushURL = "https://example.com/from-push"
NotificationCenter.default.post(
    name: Notification.Name("didReceivePushURL"),
    object: nil
)
```

Эта механика работает независимо от `pushFlowEnabled`.

## Минимальные Примечания

- Минимальная iOS: `15.0`.
- Если какой-то адаптер не передан (`nil`), соответствующая ветка просто не выполняется.
