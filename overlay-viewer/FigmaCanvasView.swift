import Cocoa
import WebKit

final class FigmaCanvasView: WKWebView {

    convenience init() {
        self.init(frame: .zero, configuration: WKWebViewConfiguration())
        translatesAutoresizingMaskIntoConstraints = false
        underPageBackgroundColor = .clear
    }

    func loadFigmaURL(_ url: URL) {
        guard let embed = FigmaCanvasView.embedURL(from: url) else { return }
        load(URLRequest(url: embed))
    }

    static func isFigmaURL(_ url: URL) -> Bool {
        url.host?.hasSuffix("figma.com") == true
    }

    private static func embedURL(from url: URL) -> URL? {
        guard isFigmaURL(url),
              let encoded = url.absoluteString
                  .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://www.figma.com/embed?embed_host=overlayviewer&url=\(encoded)")
    }
}
