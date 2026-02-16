import Foundation
import UIKit
import WebKit

/// Конфигурация запуска WebScreen.
public struct WebScreenConfiguration {
    /// Стартовый URL экрана.
    public var initialURL: URL?
    /// Альтернатива URL: прямой HTML для загрузки в WebView.
    public var htmlString: String?
    /// Промокод сценарий (в текущей логике не используется, оставлен для совместимости).
    public var promocode: String?
    /// Коллбек, вызывается в `viewDidDisappear`.
    public var onViewDidDisappear: (() -> Void)?
    /// Исходный URL для аналитики/диагностики.
    public var originalURL: URL?
    /// Значение query-параметра `app_type`.
    public var appType: String
    /// Значение query-параметра `app_id`.
    public var appID: String?
    /// Имя notification для события "пришел push URL".
    public var pushURLNotificationName: Notification.Name?

    public init(
        initialURL: URL? = nil,
        htmlString: String? = nil,
        promocode: String? = nil,
        onViewDidDisappear: (() -> Void)? = nil,
        originalURL: URL? = nil,
        appType: String = "1",
        appID: String? = nil,
        pushURLNotificationName: Notification.Name? = nil
    ) {
        self.initialURL = initialURL
        self.htmlString = htmlString
        self.promocode = promocode
        self.onViewDidDisappear = onViewDidDisappear
        self.originalURL = originalURL
        self.appType = appType
        self.appID = appID
        self.pushURLNotificationName = pushURLNotificationName
    }
}

/// Результат классификации URL.
public enum WebScreenURLDecision {
    case `internal`
    case external
    case deeplink
    case invalid
}

/// Команда роутинга, которую генерирует SDK.
public enum WebScreenRouteCommand {
    case featureApp
    case dismiss
}

/// Единый статус разрешений push-уведомлений.
public enum WebScreenRemoteNotificationsStatus {
    case allowed
    case denied
    case notDetermined
}

/// Включает/выключает опциональные ветки логики SDK.
public struct WebScreenCapabilities {
    public var pushFlowEnabled: Bool
    public var debugTokensEnabled: Bool
    public var deeplinkEnabled: Bool
    public var urlEnrichmentEnabled: Bool

    public init(
        pushFlowEnabled: Bool = true,
        debugTokensEnabled: Bool = false,
        deeplinkEnabled: Bool = true,
        urlEnrichmentEnabled: Bool = true
    ) {
        self.pushFlowEnabled = pushFlowEnabled
        self.debugTokensEnabled = debugTokensEnabled
        self.deeplinkEnabled = deeplinkEnabled
        self.urlEnrichmentEnabled = urlEnrichmentEnabled
    }
}

/// Адаптер роутинга команд SDK в навигацию приложения.
public protocol WebScreenRouting: AnyObject {
    func route(_ command: WebScreenRouteCommand)
}

/// Определяет, как обрабатывать URL.
public protocol WebScreenURLPolicy: AnyObject {
    func classify(_ url: URL) -> WebScreenURLDecision
    func openExternally(_ url: URL)
}

/// Обрабатывает deeplink-события, приходящие из SDK.
public protocol WebScreenDeepLinkHandling: AnyObject {
    func handle(_ deeplink: String)
    func executePending()
}

/// Хранит и разделяет состояние web-экрана с хост-приложением.
public protocol WebScreenStateStore: AnyObject {
    var isAgreement: Bool { get set }
    var pushURL: String? { get set }
}

/// Адаптер push-уведомлений для опционального push-flow.
public protocol WebScreenPushService: AnyObject {
    func fetchStatus(completion: @escaping (WebScreenRemoteNotificationsStatus?) -> Void)
    func register(completion: @escaping (WebScreenRemoteNotificationsStatus?) -> Void)
    func unregister(completion: @escaping (WebScreenRemoteNotificationsStatus?) -> Void)
}

/// Поставщик токенов для обогащения URL и debug-режима.
public protocol WebScreenTokenProvider: AnyObject {
    func fcmToken() -> String?
    func mindboxUUID(completion: @escaping (String) -> Void)
}

/// Агрегатор всех внешних зависимостей SDK.
public protocol WebScreenEnvironment {
    var urlPolicy: WebScreenURLPolicy? { get }
    var routing: WebScreenRouting? { get }
    var deepLinkHandler: WebScreenDeepLinkHandling? { get }
    var stateStore: WebScreenStateStore? { get }
    var pushService: WebScreenPushService? { get }
    var tokenProvider: WebScreenTokenProvider? { get }
    var capabilities: WebScreenCapabilities { get }
    var webViewProcessPool: WKProcessPool? { get }
}

/// Базовая реализация `WebScreenEnvironment` для удобной интеграции.
public struct WebScreenEnvironmentValues: WebScreenEnvironment {
    public var urlPolicy: WebScreenURLPolicy?
    public var routing: WebScreenRouting?
    public var deepLinkHandler: WebScreenDeepLinkHandling?
    public var stateStore: WebScreenStateStore?
    public var pushService: WebScreenPushService?
    public var tokenProvider: WebScreenTokenProvider?
    public var capabilities: WebScreenCapabilities
    public var webViewProcessPool: WKProcessPool?

    public init(
        urlPolicy: WebScreenURLPolicy? = nil,
        routing: WebScreenRouting? = nil,
        deepLinkHandler: WebScreenDeepLinkHandling? = nil,
        stateStore: WebScreenStateStore? = nil,
        pushService: WebScreenPushService? = nil,
        tokenProvider: WebScreenTokenProvider? = nil,
        capabilities: WebScreenCapabilities = .init(),
        webViewProcessPool: WKProcessPool? = nil
    ) {
        self.urlPolicy = urlPolicy
        self.routing = routing
        self.deepLinkHandler = deepLinkHandler
        self.stateStore = stateStore
        self.pushService = pushService
        self.tokenProvider = tokenProvider
        self.capabilities = capabilities
        self.webViewProcessPool = webViewProcessPool
    }
}

internal protocol WebScreenView: AnyObject {
    func display(url: URL)
    func display(htmlString: String, baseURL: URL?)
    func stopLoading()
    func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?)
    func sideMenuRevealable(isActive: Bool)
}
