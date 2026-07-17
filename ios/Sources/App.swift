import UIKit
import WebKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?
    let vc = ViewController()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        vc.handleDeepLink(url)
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let pay = response.notification.request.content.userInfo["pay"] as? String {
            vc.openPay(id: pay)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

class ViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    var webView: WKWebView!
    let appURL = URL(string: "https://alina3500-2-arch.github.io/avito-plan/money.html")!
    var pendingJS: String?
    var downloadDest: URL?

    override func viewDidLoad() {
        super.viewDidLoad()
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "reminders")
        cfg.applicationNameForUserAgent = "MoiDengiApp"
        webView = WKWebView(frame: view.bounds, configuration: cfg)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(webView)
        view.backgroundColor = .white
        webView.load(URLRequest(url: appURL))
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: deep links (moidengi://sms?text=..., moidengi://pay?id=...)
    func handleDeepLink(_ url: URL) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let host = url.host ?? ""
        if host == "sms" {
            let text = comps.queryItems?.first(where: { $0.name == "text" })?.value ?? ""
            if !text.isEmpty { runJS("handleSmsText(" + jsString(text) + ",{fromUrl:true})") }
        } else if host == "pay" {
            let id = comps.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            runJS("openDueSheet(" + jsString(id) + ")")
        }
    }

    func openPay(id: String) {
        runJS("openDueSheet(" + jsString(id) + ")")
    }

    func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }

    func runJS(_ js: String) {
        if webView.isLoading {
            pendingJS = js
        } else {
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let js = pendingJS {
            pendingJS = nil
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: reminders -> local notifications
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "reminders", let arr = message.body as? [[String: Any]] else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        for r in arr {
            guard let id = r["id"] as? String,
                  let name = r["name"] as? String,
                  let due = r["due"] as? String,
                  let time = r["time"] as? String else { continue }
            let rep = (r["repeat"] as? String) ?? "none"
            let dayBefore = (r["dayBefore"] as? Bool) ?? true
            let dueParts = due.split(separator: "-").compactMap { Int($0) }
            let timeParts = time.split(separator: ":").compactMap { Int($0) }
            guard dueParts.count == 3, timeParts.count >= 2 else { continue }
            var dc = DateComponents()
            dc.year = dueParts[0]; dc.month = dueParts[1]; dc.day = dueParts[2]
            dc.hour = timeParts[0]; dc.minute = timeParts[1]
            let cal = Calendar.current
            guard let dueDate = cal.date(from: dc) else { continue }
            var amount = ""
            if let d = r["amount"] as? Double {
                amount = String(format: "%.0f", d)
            } else if let i = r["amount"] as? Int {
                amount = String(i)
            }
            let body = amount.isEmpty ? name : name + " — " + amount + " ₽"
            scheduleOne(id: id, payId: id, title: "Пора оплатить", body: body, date: dueDate, rep: rep)
            if dayBefore, let prev = cal.date(byAdding: .day, value: -1, to: dueDate) {
                scheduleOne(id: id + "_pre", payId: id, title: "Завтра оплатить", body: body, date: prev, rep: rep)
            }
        }
    }

    func scheduleOne(id: String, payId: String, title: String, body: String, date: Date, rep: String) {
        let cal = Calendar.current
        var comps: DateComponents
        var repeats = true
        switch rep {
        case "weekly":
            comps = cal.dateComponents([.weekday, .hour, .minute], from: date)
        case "monthly":
            comps = cal.dateComponents([.day, .hour, .minute], from: date)
        case "yearly":
            comps = cal.dateComponents([.month, .day, .hour, .minute], from: date)
        default:
            if date < Date() { return }
            comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            repeats = false
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["pay": payId]
        let trig = UNCalendarNotificationTrigger(dateMatching: comps, repeats: repeats)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trig),
            withCompletionHandler: nil)
    }

    // MARK: JS alert/confirm/prompt
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "ОК", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "ОК", style: .default) { [weak a] _ in
            completionHandler(a?.textFields?.first?.text)
        })
        present(a, animated: true)
    }

    // MARK: downloads (CSV, backup JSON, .ics) -> share sheet
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let name = suggestedFilename.isEmpty ? "file" : suggestedFilename
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        downloadDest = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDest else { return }
        DispatchQueue.main.async {
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            av.popoverPresentationController?.sourceView = self.view
            self.present(av, animated: true)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDest = nil
    }
}
