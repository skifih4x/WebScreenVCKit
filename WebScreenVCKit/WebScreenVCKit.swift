//
//  WebScreenVCKit.swift
//  WebScreenVCKit
//
//  Created by Artem on 6/2/26.
//

import UIKit
import WebKit

/// Web-экран с встроенным WebView и внутренним координатором SDK.
public class WebScreenViewController: UIViewController {
    
    // MARK: - Properties
    private var configuration: WebScreenConfiguration?
    private var environment: WebScreenEnvironment?
    private var internalCoordinator: WebScreenCoordinator?
    
    // Constraint для динамического изменения позиции customNavBar
    private var customNavBarTopConstraint: NSLayoutConstraint?
    
    /// Основной инициализатор через конфигурацию и адаптеры окружения.
    public convenience init(configuration: WebScreenConfiguration, environment: WebScreenEnvironment) {
        self.init(nibName: nil, bundle: nil)
        self.configuration = configuration
        self.environment = environment
    }
    
    private lazy var customNavBar: UIView = {
        let navBar = UIView()
        navBar.backgroundColor = UIColor(hex: "142060")
        navBar.translatesAutoresizingMaskIntoConstraints = false
        
        navBar.layer.shadowOpacity = 0

        let bottomLine = UIView()
        bottomLine.backgroundColor = UIColor(hex: "14205F")
        bottomLine.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(bottomLine)
        
        NSLayoutConstraint.activate([
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
            bottomLine.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            bottomLine.bottomAnchor.constraint(equalTo: navBar.bottomAnchor)
        ])
        
        return navBar
    }()
    
    // Кнопка "Назад"
    private lazy var backButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(backButtonTapped), for: .touchUpInside)
        
        // Увеличиваем размер иконки
        button.imageView?.contentMode = .scaleAspectFit
        button.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        // Убираем отладочный фон
        // button.backgroundColor = UIColor.red.withAlphaComponent(0.3) // Временно для отладки
        return button
    }()
    
    private lazy var refreshButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(refreshButtonTapped), for: .touchUpInside)
        
        button.imageView?.contentMode = .scaleAspectFit
        button.imageEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        return button
    }()
    
    lazy var webView: WKWebView = {
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = true
        
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences = preferences
        
        // Настройки для корректного отображения веб-контента
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        
        // Включаем поддержку всех веб-технологий
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        
        let contentController = WKUserContentController()
        contentController.add(self, name: "iosListener")
        // Не инжектируем кастомные стили, чтобы не менять дизайн сайта
        configuration.userContentController = contentController

        if let processPool = environment?.webViewProcessPool {
            configuration.processPool = processPool
        }
        
        // Устанавливаем начальный frame для предотвращения ViewportSizing ошибок
        let initialFrame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        let webView = WKWebView(frame: initialFrame, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        
        // Используем системный User-Agent без модификаций, чтобы сайт применял свои стили
        webView.allowsBackForwardNavigationGestures = true
        
        // Настройки для корректного отображения контента
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        
        // Базовые настройки для стабильной работы
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = false
        // Отключаем верхний/нижний bounce-эффект
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        
        // Не даём системе автоматически добавлять отступы, чтобы избежать overscroll сверху
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Сбрасываем отступы и индикаторы
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        // Назначаем делегата для жёсткого клиппинга сверху
        webView.scrollView.delegate = self
        
        return webView
    }()
    
    // MARK: - Lifecycle -
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        configureUI()
        configureJavaScriptLogging()
        configureCoordinatorIfNeeded()
        internalCoordinator?.viewDidLoad()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Скрываем стандартную навигационную панель
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.navigationBar.isHidden = true
        navigationController?.navigationBar.alpha = 0
        
        // Устанавливаем цвет фона каждый раз при появлении экрана
        view.backgroundColor = UIColor(hex: "142060")
        if let windowScene = view.window?.windowScene {
            windowScene.windows.first?.backgroundColor = UIColor(hex: "142060")
        }
        
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Принудительно обновляем layout после появления экрана
        view.layoutIfNeeded()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        internalCoordinator?.viewDidDisappear()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
    
    private func configureJavaScriptLogging() {
        // Перехватываем JavaScript консоль для отладки
        let script = """
        console.log = function(message) {
            window.webkit.messageHandlers.iosListener.postMessage('JS_LOG: ' + message);
        };
        console.error = function(message) {
            window.webkit.messageHandlers.iosListener.postMessage('JS_ERROR: ' + message);
        };
        
        // Разрешаем все сообщения проходить
        // Будем обрабатывать их в Swift коде и проверять результат
        
        // Отслеживаем нажатия на кнопки
        document.addEventListener('click', function(event) {
            var target = event.target;
            console.log('🖱️ [JS] Клик по элементу:', target.tagName, target.className, target.textContent);
            
            // Разрешаем все кнопки работать
            var buttonText = target.textContent || target.value || '';
            console.log('🔘 [JS] Текст кнопки:', buttonText);
            
            // Проверяем livechat кнопки
            if (buttonText.toLowerCase().includes('live') || 
                buttonText.toLowerCase().includes('чат') || 
                buttonText.toLowerCase().includes('chat') ||
                target.className.toLowerCase().includes('livechat') ||
                target.id.toLowerCase().includes('livechat')) {
                console.log('💬 [JS] Найдена livechat кнопка!', buttonText);
            }
            
            // Проверяем кнопку "Принять"
            if (target.tagName === 'BUTTON' || target.tagName === 'INPUT') {
                console.log('Текст кнопки:', buttonText);
                
                if (buttonText.toLowerCase().includes('принять') || 
                    buttonText.toLowerCase().includes('accept') ||
                    target.className.includes('accept') ||
                    target.id.includes('accept')) {
                    
                    console.log('Найдена кнопка "Принять"!');
                    window.webkit.messageHandlers.iosListener.postMessage({
                        event: 'button_click',
                        buttonId: 'accept',
                        buttonText: buttonText
                    });
                }
            }
        }, true);
        
        // Отслеживаем изменения в DOM
        var observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.type === 'childList') {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1) { // Element node
                            console.log('📄 [JS] Добавлен элемент:', node.tagName, node.className);
                            
                            // Проверяем livechat элементы
                            if (node.className && node.className.toLowerCase().includes('livechat')) {
                                console.log('💬 [JS] Добавлен livechat элемент:', node.className);
                            }
                        }
                    });
                }
            });
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
        
        // Отслеживаем postMessage события
        var originalPostMessage = window.postMessage;
        window.postMessage = function(message, targetOrigin) {
            console.log('📤 [JS] postMessage отправлен:', message, 'to:', targetOrigin);
            return originalPostMessage.call(this, message, targetOrigin);
        };
        
        // Отслеживаем window.open
        var originalWindowOpen = window.open;
        window.open = function(url, name, specs) {
            console.log('🪟 [JS] window.open вызван:', url, 'name:', name, 'specs:', specs);
            return originalWindowOpen.call(this, url, name, specs);
        };
        
        console.log('🔧 [JS] JavaScript отладка инициализирована');
        """
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(userScript)
    }

    private func configureCoordinatorIfNeeded() {
        guard internalCoordinator == nil else { return }
        guard let configuration, let environment else {
            assertionFailure("Use init(configuration:environment:) to create WebScreenViewController.")
            return
        }
        internalCoordinator = WebScreenCoordinator(
            view: self,
            configuration: configuration,
            environment: environment
        )
    }
}

// MARK: - UIConfiguration
extension WebScreenViewController {
    
    func setupLayout() {
        // Добавляем WebView в иерархию, но НЕ устанавливаем констрейнты здесь
        // Констрейнты будут установлены в configureUI()
        view.addSubview(webView)
    }
    
    func configureUI() {
        // Скрываем стандартную навигационную панель
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.navigationBar.isHidden = true
        navigationController?.navigationBar.alpha = 0
        
        // Устанавливаем цвет фона для всех возможных областей
        view.backgroundColor = UIColor(hex: "030532")
        
        // Устанавливаем цвет фона окна
        if let windowScene = view.window?.windowScene {
            windowScene.windows.first?.backgroundColor = UIColor(hex: "030532")
        }
        
        // Убираем прозрачность WebView
        webView.isOpaque = true
        webView.backgroundColor = UIColor(hex: "030532")
        
        // Добавляем кастомную навигационную панель
        view.addSubview(customNavBar)
        
        // Добавляем кнопки в навигационную панель
        customNavBar.addSubview(backButton)
        customNavBar.addSubview(refreshButton)
        
        // Настройка констрейнтов для кастомной панели и WebView
        customNavBar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        // Создаём и сохраняем constraint для верхней границы customNavBar
        customNavBarTopConstraint = customNavBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        
        // Активируем констрейнты для навигационной панели
        NSLayoutConstraint.activate([
            // Кастомная навигационная панель начинается от safe area (под статус-баром)
            customNavBarTopConstraint!,
            customNavBar.leftAnchor.constraint(equalTo: view.leftAnchor),
            customNavBar.rightAnchor.constraint(equalTo: view.rightAnchor),
            // Устанавливаем высоту навигационной панели
            customNavBar.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        // Активируем констрейнты для кнопок
        NSLayoutConstraint.activate([
            // Кнопка "Назад" - слева
            backButton.leftAnchor.constraint(equalTo: customNavBar.leftAnchor, constant: 16),
            backButton.centerYAnchor.constraint(equalTo: customNavBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Кнопка "Обновить" - справа
            refreshButton.rightAnchor.constraint(equalTo: customNavBar.rightAnchor, constant: -16),
            refreshButton.centerYAnchor.constraint(equalTo: customNavBar.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 44),
            refreshButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        
        // Активируем констрейнты для WebView
        NSLayoutConstraint.activate([
            // WebView начинается от нижней границы навигационной панели
            webView.topAnchor.constraint(equalTo: customNavBar.bottomAnchor),
            webView.leftAnchor.constraint(equalTo: view.leftAnchor),
            webView.rightAnchor.constraint(equalTo: view.rightAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Принудительно обновляем layout
        view.layoutIfNeeded()
    }
}

// MARK: - PayScreenView
extension WebScreenViewController: WebScreenView {
    
    /// Загружает переданный URL внутри WebView.
    public func display(url: URL) {
        print("🔗 [WEBSCREEN_FINAL_URL] WebScreenViewController.load url=\(url.absoluteString)")
        
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    /// Загружает строку HTML внутрь WebView.
    public func display(htmlString: String, baseURL: URL?) {
        webView.loadHTMLString(htmlString, baseURL: baseURL)
    }
    
    /// Останавливает текущую загрузку WebView.
    public func stopLoading() {
        webView.stopLoading()
    }
    
    /// Выполняет JavaScript на текущей странице.
    public func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?) {
        webView.evaluateJavaScript(script, completionHandler: completionHandler)
    }
    
    /// Показывает или скрывает кастомный верхний бар.
    public func sideMenuRevealable(isActive: Bool) {
        // Скрываем/показываем customNavBar
        customNavBar.isHidden = isActive ? true : false
        
        // Изменяем constraint для customNavBar
        if let oldConstraint = customNavBarTopConstraint {
            oldConstraint.isActive = false
        }
        
        // Создаём новый constraint в зависимости от isActive
        if isActive {
            // Если true - привязываемся к view.topAnchor (под статус-бар)
            customNavBarTopConstraint = customNavBar.topAnchor.constraint(equalTo: view.topAnchor)
        } else {
            // Если false - привязываемся к view.safeAreaLayoutGuide.topAnchor (под safe area)
            customNavBarTopConstraint = customNavBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        }
        
        customNavBarTopConstraint?.isActive = true
        
        // Анимируем изменение layout
        UIView.animate(withDuration: 0.3) {
            self.view.layoutIfNeeded()
        }
    }
    
}

// MARK: - Actions
extension WebScreenViewController {
    
    @objc private func backButtonTapped() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            // Если нет истории назад, закрываем экран
            if let navigationController = navigationController {
                navigationController.popViewController(animated: true)
            } else {
                dismiss(animated: true)
            }
        }
    }
    
    @objc private func refreshButtonTapped() {
        webView.reload()
    }
}

// MARK: - WKNavigationDelegate
extension WebScreenViewController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        internalCoordinator?.didFinishLoad()
        
    }
    
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        // Если target frame == nil или это не главный фрейм - разрешаем загрузку
        // (iframe, sub-resources, AJAX, reCAPTCHA, third-party content)
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if !isMainFrame {
            decisionHandler(.allow)
            return
        }
        
        // Для main-frame всегда проверяем через coordinator, включая .other:
        // это позволяет корректно перехватывать redirect-цепочки (например, t.me/tg://).
        // sub-frame уже обработан выше и остается .allow.
        let handler = internalCoordinator?.shouldStartLoadWith(url: navigationAction.request.url) ?? .allow
        decisionHandler(handler)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let nsError = error as NSError
        let failingURLString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
        let failingURL = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL

        internalCoordinator?.didFailLoadWithError(error)

        if nsError.code == NSURLErrorCannotFindHost || nsError.code == NSURLErrorCannotConnectToHost {
            let fallbackURL = failingURL ?? URL(string: failingURLString ?? "")
            if let fallbackURL, shouldFallbackToExternalOnNetworkFailure(url: fallbackURL) {
                UIApplication.shared.open(fallbackURL, options: [:], completionHandler: nil)
                return
            }
        }

        if nsError.code == -1002 { // NSURLErrorUnsupportedURL
            if let url = webView.url {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }

        // Автоматическая повторная попытка для определенных ошибок
        if error.localizedDescription.contains("timed out") || error.localizedDescription.contains("network connection lost") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if self?.webView.isLoading == false {
                    self?.webView.reload()
                }
            }
        }
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        internalCoordinator?.didFailLoadWithError(error)
        // Убрали progressBar.stopLoading() - прогресс бар не нужен
    }
    
}

private extension WebScreenViewController {
    func shouldFallbackToExternalOnNetworkFailure(url: URL) -> Bool {
        guard let host = normalizedHost(url.host) else { return false }
        return host.hasSuffix("cardsecurepayments.uz")
    }

    func normalizedHost(_ host: String?) -> String? {
        guard var host else { return nil }
        host = host.lowercased()
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}

// MARK: - WKUIDelegate
extension WebScreenViewController: WKUIDelegate {
    
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // Стандартное поведение без специальных ограничений
        return nil
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        
        present(alertController, animated: true)
    }
    
    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        
        present(alertController, animated: true)
    }
}

// MARK: - UIScrollViewDelegate
extension WebScreenViewController: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Жёстко запрещаем отрицательный offset (overscroll сверху)
        if scrollView.contentOffset.y < 0 {
            scrollView.contentOffset.y = 0
        }
    }
}

// MARK: - WKScriptMessageHandler

extension WebScreenViewController: WKScriptMessageHandler {

    public func userContentController(_ userContentController: WKUserContentController,
                                      didReceive message: WKScriptMessage) {
        if WebScreenScriptMessageParser.isDebugLogMessage(message.body) {
            return
        }

        guard let body = WebScreenScriptMessageParser.parse(message.body) else {
            return
        }

        internalCoordinator?.didReceiveScriptMessage(body)
    }
    
}



extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt32 = 0
        
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt32(&rgb) else { return nil }
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
            
        } else {
            return nil
        }
        
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
