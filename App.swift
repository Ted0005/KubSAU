import UIKit
import WebKit
import UserNotifications
import WidgetKit

// Учёба ЮФ2611: нативная оболочка для index.html.
// Страница лежит внутри приложения и открывается по адресу uchyoba://local/index.html.
// uchyoba://local/proxy?url=... загружает расписание с s.kubsau.ru средствами iOS (без CORS и сторонних прокси).

private let bg = UIColor(red: 0.102, green: 0.114, blue: 0.106, alpha: 1) // #1a1d1b, как фон страницы

@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    // уведомление показывается баннером и со звуком, даже если приложение открыто
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = bg
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

// MARK: - Файлы приложения и загрузка расписания

final class LocalScheme: NSObject, WKURLSchemeHandler {
    private var live = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        live.insert(id)
        guard let url = task.request.url else { fail(task, id, URLError(.badURL)); return }

        if url.path == "/proxy" {
            let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "url" })?.value ?? ""
            // пропускаем только сайт расписания
            guard let target = URL(string: raw), target.scheme == "https", target.host == "s.kubsau.ru" else {
                finish(task, id, status: 403, type: "text/plain", data: Data()); return
            }
            var req = URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            req.setValue("text/html", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: req) { data, resp, err in
                DispatchQueue.main.async {
                    if let http = resp as? HTTPURLResponse, let data = data {
                        let type = http.value(forHTTPHeaderField: "Content-Type") ?? "text/html"
                        self.finish(task, id, status: http.statusCode, type: type, data: data)
                    } else {
                        self.fail(task, id, err ?? URLError(.unknown))
                    }
                }
            }.resume()
            return
        }

        var name = String(url.path.dropFirst())
        if name.isEmpty { name = "index.html" }
        guard !name.contains(".."),
              let base = Bundle.main.resourceURL,
              let data = try? Data(contentsOf: base.appendingPathComponent(name)) else {
            finish(task, id, status: 404, type: "text/plain", data: Data()); return
        }
        finish(task, id, status: 200, type: mime(name), data: data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        live.remove(ObjectIdentifier(task))
    }

    private func finish(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, status: Int, type: String, data: Data) {
        guard live.remove(id) != nil, let url = task.request.url,
              let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": type,
                                                        "Cache-Control": "no-store",
                                                        "Access-Control-Allow-Origin": "*"]) else { return }
        task.didReceive(resp)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, _ id: ObjectIdentifier, _ error: Error) {
        guard live.remove(id) != nil else { return }
        task.didFailWithError(error)
    }

    private func mime(_ name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Экран со страницей

final class WebViewController: UIViewController, WKUIDelegate, WKScriptMessageHandlerWithReply {
    private var web: WKWebView!

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(LocalScheme(), forURLScheme: "uchyoba")
        cfg.websiteDataStore = .default() // постоянное хранилище: задачи, конспекты, фото
        let uc = cfg.userContentController
        uc.addUserScript(WKUserScript(source: "window.NATIVE=1;", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        uc.addScriptMessageHandler(self, contentWorld: .page, name: "saveFile")
        uc.addScriptMessageHandler(self, contentWorld: .page, name: "notify")
        uc.addScriptMessageHandler(self, contentWorld: .page, name: "widget")

        web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = bg
        web.scrollView.backgroundColor = bg
        web.scrollView.contentInsetAdjustmentBehavior = .never // отступы задаёт сама страница через safe-area
        web.allowsBackForwardNavigationGestures = false
        view = web
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        web.load(URLRequest(url: URL(string: "uchyoba://local/index.html")!))
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // alert / confirm / prompt: без этого кнопки «Удалить» и «Восстановить» не работают
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { [weak a] _ in
            completionHandler(a?.textFields?.first?.text)
        })
        present(a, animated: true)
    }

    // напоминания о задачах: страница присылает полный список, приложение заменяет им все запланированные уведомления
    private func scheduleNotifications(_ items: [[String: Any]], reply: @escaping (Any?, String?) -> Void) {
        let center = UNUserNotificationCenter.current()
        let apply = {
            center.removeAllPendingNotificationRequests()
            let now = Date().timeIntervalSince1970
            for it in items {
                guard let id = it["id"] as? String,
                      let title = it["title"] as? String,
                      let body = it["body"] as? String,
                      let at = (it["at"] as? NSNumber)?.doubleValue else { continue }
                let delay = at / 1000 - now
                if delay < 2 { continue }
                let c = UNMutableNotificationContent()
                c.title = title
                c.body = body
                c.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                center.add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
            }
        }
        center.getNotificationSettings { s in
            let done = { (ok: Bool) in DispatchQueue.main.async { reply(ok, nil) } }
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                apply(); done(true)
            case .notDetermined:
                if items.isEmpty { done(false); return } // спрашиваем разрешение, когда появилась первая задача
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { apply() }
                    done(granted)
                }
            default:
                done(false)
            }
        }
    }

    // копия данных: страница передаёт текст, приложение открывает «Поделиться» (Сохранить в Файлы, iCloud)
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        if message.name == "widget" {
            // данные для виджета: пишем в общее хранилище (App Group); без него просто пропускаем
            let json = ((message.body as? [String: Any])?["json"] as? String) ?? ""
            var ok = false
            if let data = json.data(using: .utf8),
               let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ru.arman.uchyoba") {
                ok = (try? data.write(to: dir.appendingPathComponent("snapshot.json"), options: .atomic)) != nil
                if ok { WidgetCenter.shared.reloadAllTimelines() }
            }
            replyHandler(ok, nil)
            return
        }
        if message.name == "notify" {
            let items = ((message.body as? [String: Any])?["items"] as? [[String: Any]]) ?? []
            scheduleNotifications(items, reply: replyHandler)
            return
        }
        guard let body = message.body as? [String: Any],
              let text = body["text"] as? String,
              let data = text.data(using: .utf8) else { replyHandler(false, nil); return }
        let name = ((body["name"] as? String) ?? "uchyoba.json").replacingOccurrences(of: "/", with: "_")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: file, options: .atomic) } catch { replyHandler(false, nil); return }

        var replied = false
        let vc = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, done, _, _ in
            if replied { return }
            replied = true
            replyHandler(done, nil)
        }
        vc.popoverPresentationController?.sourceView = view
        present(vc, animated: true)
    }
}
