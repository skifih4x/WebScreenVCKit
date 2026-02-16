import Foundation
import UIKit
import WebKit

internal final class WebScreenCoordinator {
    private weak var view: WebScreenView?
    private let configuration: WebScreenConfiguration
    private let environment: WebScreenEnvironment

    private var currentURL: URL?
    private var errorsCount = 0
    private var isSideMenuRevealable = false
    private var remoteNotificationsListStatus: WebScreenRemoteNotificationsStatus?
    private var pushURLObserver: NSObjectProtocol?

    init(view: WebScreenView, configuration: WebScreenConfiguration, environment: WebScreenEnvironment) {
        self.view = view
        self.configuration = configuration
        self.environment = environment
        self.currentURL = configuration.initialURL
    }

    deinit {
        removeNotificationObservers()
    }

    func shouldStartLoadWith(url: URL?) -> WKNavigationActionPolicy {
        let urlString = url?.absoluteString ?? ""

        if urlString == "about:blank" {
            return .allow
        }

        guard let url else {
            return .allow
        }

        guard let urlPolicy = environment.urlPolicy else { return .allow }

        switch urlPolicy.classify(url) {
        case .internal:
            return .allow

        case .external:
            urlPolicy.openExternally(url)
            return .cancel

        case .deeplink:
            if environment.capabilities.deeplinkEnabled, let deepLinkHandler = environment.deepLinkHandler {
                deepLinkHandler.handle(url.absoluteString)
                deepLinkHandler.executePending()
            } else {
                urlPolicy.openExternally(url)
            }
            return .cancel

        case .invalid:
            return .cancel
        }
    }

    func didFailLoadWithError(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code == NSURLErrorCannotConnectToHost else {
            return
        }

        errorsCount += 1
        guard errorsCount < 5 else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.display()
        }
    }

    func didFinishLoad() {
        errorsCount = 0

        checkContentAndRequestNotificationsIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.didReceivePushURL()
        }

        executeDeeplinkAfterWebViewLoad()
    }

    func didReceiveScriptMessage(_ body: [String: Any]) {
        if let type = body["type"] as? String,
           type == "isHideHeader",
           let valueString = body["value"] as? String {
            setSideMenuRevealable((valueString as NSString).boolValue)
        }

        if let event = body["event"] as? String {
            switch event {
            case "is_agreement":
                if let isAgreement = body["value"] as? Bool, isAgreement {
                    environment.stateStore?.isAgreement = true
                    didReceiveAgreement()
                }

            case "button_click":
                if let buttonId = body["buttonId"] as? String,
                   buttonId == "accept" || buttonId.contains("принять") {
                    environment.stateStore?.isAgreement = true
                    didReceiveAgreement()
                }

            default:
                break
            }
            return
        }

        if let type = body["type"] as? String {
            switch type {
            case "livechat":
                break

            case "dismiss":
                route(.dismiss)

            default:
                break
            }
            return
        }

        if let deeplink = body["deeplink"] as? String {
            guard environment.capabilities.deeplinkEnabled else { return }

            guard !deeplink.contains("livechat") else {
                return
            }

            guard let deepLinkHandler = environment.deepLinkHandler else { return }

            deepLinkHandler.handle(deeplink)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                deepLinkHandler.executePending()
            }
        }
    }

    func didReceiveAgreement() {
        route(.featureApp)
    }

    func viewDidLoad() {
        addNotificationObservers()

        if let pushURLString = environment.stateStore?.pushURL,
           let pushURL = URL(string: pushURLString) {
            currentURL = pushURL
            environment.stateStore?.pushURL = nil
        }

        display()

        if environment.capabilities.deeplinkEnabled {
            environment.deepLinkHandler?.executePending()
        }
    }

    func viewDidDisappear() {
        configuration.onViewDidDisappear?()
        removeNotificationObservers()
    }

    private func addNotificationObservers() {
        guard let notificationName = configuration.pushURLNotificationName else {
            return
        }

        pushURLObserver = NotificationCenter.default.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.didReceivePushURL()
        }
    }

    private func removeNotificationObservers() {
        if let pushURLObserver {
            NotificationCenter.default.removeObserver(pushURLObserver)
            self.pushURLObserver = nil
        }
    }

    private func setSideMenuRevealable(_ isActive: Bool) {
        guard isSideMenuRevealable != isActive else { return }
        isSideMenuRevealable = isActive

        DispatchQueue.main.async { [weak self] in
            self?.view?.sideMenuRevealable(isActive: isActive)
        }
    }

    private func route(_ command: WebScreenRouteCommand) {
        guard let routing = environment.routing else { return }
        routing.route(command)
    }

    private func didReceivePushURL() {
        guard let pushURLString = environment.stateStore?.pushURL,
              let pushURL = URL(string: pushURLString) else {
            return
        }

        present(url: pushURL) { [weak self] finalURL in
            guard let self else { return }
            DispatchQueue.main.async {
                self.currentURL = finalURL
                self.environment.stateStore?.pushURL = nil
                self.view?.display(url: finalURL)
            }
        }
    }

    private func display() {
        if configuration.promocode != nil { return }

        if let htmlString = configuration.htmlString {
            view?.display(htmlString: htmlString, baseURL: currentURL ?? configuration.initialURL)
            return
        }

        if let initialURL = currentURL ?? configuration.initialURL {
            present(url: initialURL) { [weak self] finalURL in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.currentURL = finalURL
                    self.view?.display(url: finalURL)
                }
            }
        }
    }

    private func present(url: URL, completion: @escaping (URL) -> Void) {
        guard environment.capabilities.urlEnrichmentEnabled else {
            completion(url)
            return
        }

        let shouldAttachAppID: Bool
        if let stateStore = environment.stateStore {
            shouldAttachAppID = !stateStore.isAgreement
        } else {
            shouldAttachAppID = false
        }

        WebScreenURLBuilder.enrich(
            url: url,
            appType: configuration.appType,
            appID: configuration.appID,
            shouldAttachAppID: shouldAttachAppID,
            tokenProvider: environment.tokenProvider,
            completion: completion
        )
    }

    private func checkContentAndRequestNotificationsIfNeeded() {
        let javascript = """
        (function() {
            var buttons = document.querySelectorAll('button, input[type="button"], input[type="submit"], [role="button"]');
            var hasAcceptButton = false;

            for (var i = 0; i < buttons.length; i++) {
                var buttonText = (buttons[i].innerText || buttons[i].textContent || buttons[i].value || '').toLowerCase();
                if (buttonText.includes('принять') ||
                    buttonText.includes('accept') ||
                    buttonText.includes('agree') ||
                    buttonText.includes('согласен') ||
                    buttonText.includes('согласиться') ||
                    buttonText.includes('ok') ||
                    buttonText.includes('continue') ||
                    buttonText.includes('продолжить')) {
                    hasAcceptButton = true;
                    break;
                }
            }

            var bodyText = (document.body.innerText || document.body.textContent || '').toLowerCase();
            var hasAgreementText = bodyText.includes('пользовательское соглашение') ||
                                   bodyText.includes('пользовательского соглашения') ||
                                   bodyText.includes('user agreement') ||
                                   bodyText.includes('terms of service') ||
                                   bodyText.includes('terms and conditions') ||
                                   bodyText.includes('privacy policy') ||
                                   bodyText.includes('политика конфиденциальности') ||
                                   bodyText.includes('условия использования') ||
                                   bodyText.includes('terms of use') ||
                                   bodyText.includes('license agreement') ||
                                   bodyText.includes('лицензионное соглашение') ||
                                   bodyText.includes('согласие') ||
                                   bodyText.includes('consent') ||
                                   bodyText.includes('мобильного приложения') ||
                                   bodyText.includes('mobile application');

            var hasFormElements = document.querySelector('input[type="checkbox"]') ||
                                  document.querySelector('form') ||
                                  document.querySelector('[class*="agreement"]') ||
                                  document.querySelector('[class*="consent"]') ||
                                  document.querySelector('[class*="terms"]') ||
                                  document.querySelector('[id*="agreement"]') ||
                                  document.querySelector('[id*="consent"]') ||
                                  document.querySelector('[id*="terms"]');

            return {
                hasAcceptButton: hasAcceptButton,
                hasAgreementText: hasAgreementText,
                hasFormElements: !!hasFormElements
            };
        })();
        """

        view?.evaluateJavaScript(javascript) { [weak self] result, error in
            guard let self else { return }
            guard error == nil else { return }

            let dict = result as? [String: Any]
            let hasAcceptButton = dict?["hasAcceptButton"] as? Bool ?? false
            let hasAgreementText = dict?["hasAgreementText"] as? Bool ?? false
            let hasFormElements = dict?["hasFormElements"] as? Bool ?? false
            let hasAgreementContent = hasAcceptButton || hasAgreementText || hasFormElements

            guard !hasAgreementContent else { return }

            if self.environment.capabilities.pushFlowEnabled {
                self.fetchRemoteNotificationsStatus()
            }

            if self.environment.capabilities.debugTokensEnabled {
                self.showTokensDebugAlert()
            }
        }
    }

    private func fetchRemoteNotificationsStatus() {
        guard let pushService = environment.pushService else { return }

        pushService.fetchStatus { [weak self] status in
            self?.fetchedRemoteNotificationsStatus(with: status)
        }
    }

    private func fetchedRemoteNotificationsStatus(with status: WebScreenRemoteNotificationsStatus?) {
        guard remoteNotificationsListStatus != .allowed && remoteNotificationsListStatus != .denied else {
            remoteNotificationsListStatus = status
            return
        }

        guard let pushService = environment.pushService else { return }

        if remoteNotificationsListStatus == nil {
            pushService.register { [weak self] status in
                self?.remoteNotificationsListStatus = status
            }
            return
        }

        if remoteNotificationsListStatus != status {
            if status != .denied {
                pushService.register { [weak self] status in
                    self?.remoteNotificationsListStatus = status
                }
            } else {
                pushService.unregister { [weak self] status in
                    self?.remoteNotificationsListStatus = status
                }
            }
            return
        }

        remoteNotificationsListStatus = status
    }

    private func executeDeeplinkAfterWebViewLoad() {
        guard environment.capabilities.deeplinkEnabled else { return }
        guard let deepLinkHandler = environment.deepLinkHandler else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            deepLinkHandler.executePending()
        }
    }

    private func showTokensDebugAlert() {
        guard let tokenProvider = environment.tokenProvider else { return }

        let firebaseToken = tokenProvider.fcmToken() ?? "Не получен"

        tokenProvider.mindboxUUID { [weak self] mindboxUUID in
            DispatchQueue.main.async {
                guard let self,
                      let viewController = self.view as? UIViewController else {
                    return
                }

                let alert = UIAlertController(
                    title: "Токены приложения",
                    message: nil,
                    preferredStyle: .alert
                )

                let message = """
                Firebase Token:
                \(firebaseToken)

                Mindbox UUID:
                \(mindboxUUID)
                """

                alert.message = message

                alert.addAction(UIAlertAction(title: "Копировать Firebase Token", style: .default) { _ in
                    UIPasteboard.general.string = firebaseToken
                })

                alert.addAction(UIAlertAction(title: "Копировать Mindbox UUID", style: .default) { _ in
                    UIPasteboard.general.string = mindboxUUID
                })

                alert.addAction(UIAlertAction(title: "Копировать все", style: .default) { _ in
                    let allTokens = "Firebase Token: \(firebaseToken)\nMindbox UUID: \(mindboxUUID)"
                    UIPasteboard.general.string = allTokens
                })

                alert.addAction(UIAlertAction(title: "Закрыть", style: .cancel))
                viewController.present(alert, animated: true)
            }
        }
    }

}
