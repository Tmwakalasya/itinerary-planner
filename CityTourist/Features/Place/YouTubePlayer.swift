import SwiftUI
import WebKit
import Observation

@MainActor @Observable
final class PlaceVideoPlayback {
    enum State: Equatable {
        case loading, ready, playing, paused, ended, failed(String)
    }
    private(set) var state: State = .loading

    func receive(event: String, code: Int? = nil) {
        // A late ready event must not erase an error/timeout or restart a player.
        if case .failed = state { return }
        switch event {
        case "ready": if state == .loading { state = .ready }
        case "state":
            switch code {
            case 1: state = .playing
            case 2: state = .paused
            case 0: state = .ended
            default: break
            }
        case "error":
            switch code {
            case 100, 101, 150:
                fail("This video can’t play here. You can try watching it on YouTube.")
            case 153:
                fail("YouTube couldn’t verify this player. Try again or watch on YouTube.")
            default:
                fail("The video couldn’t load. Check your connection and try again.")
            }
        default: break
        }
    }

    func fail(_ message: String) { state = .failed(message) }
    func timedOut() {
        if state == .loading { fail("The video is taking too long to load. Check your connection and try again.") }
    }
}

/// YouTube's own embedded player, which owns playback and its controls, as
/// YouTube's terms require. It's only created once a video is tapped; the
/// cards on a place page are just thumbnails.
struct YouTubePlayer: UIViewRepresentable {
    let videoID: String
    let playback: PlaceVideoPlayback
    var isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "video")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.accessibilityIdentifier = "placeVideoPlayer"
        let origin = Self.origin(bundleID: Bundle.main.bundleIdentifier ?? "com.tmwakalasya.citytourist")
        webView.loadHTMLString(Self.html(videoID: videoID, origin: origin), baseURL: origin)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.playback = playback
        if !isActive { webView.evaluateJavaScript("window.pauseVideo && window.pauseVideo();", completionHandler: nil) }
        // Returning to the app never starts a video on the user's behalf.
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.isInvalidated = true
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "video")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    static func origin(bundleID: String) -> URL {
        URL(string: "https://\(bundleID.lowercased())")!
    }

    static func html(videoID: String, origin: URL) -> String {
        // Values are YouTube's IDs and our bundle ID, serialized rather than
        // interpolated as JavaScript string literals.
        let options: [String: Any] = [
            "videoId": videoID, "width": "100%", "height": "100%",
            "playerVars": ["autoplay": 0, "controls": 1, "playsinline": 1,
                           "rel": 0, "origin": origin.absoluteString]
        ]
        let data = try! JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
        let json = String(decoding: data, as: UTF8.self)
        return """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body,#player{width:100%;height:100%;margin:0;background:#000;overflow:hidden}</style>
        </head><body><div id="player"></div><script>
        var player;
        function notify(event, code) {
          window.webkit.messageHandlers.video.postMessage({event:event,code:code === undefined ? null : code});
        }
        window.pauseVideo = function() { if (player && player.pauseVideo) player.pauseVideo(); };
        document.addEventListener('visibilitychange', function() { if(document.hidden) window.pauseVideo(); });
        window.onYouTubeIframeAPIReady = function() {
          var options = \(json);
          options.events = {
            onReady: function(e) { e.target.mute(); notify('ready'); },
            onStateChange: function(e) { notify('state', e.data); },
            onError: function(e) { notify('error', e.data); }
          };
          player = new YT.Player('player', options);
        };
        </script><script src="https://www.youtube.com/iframe_api" onerror="notify('error',0)"></script>
        </body></html>
        """
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        var playback: PlaceVideoPlayback
        var isInvalidated = false
        init(playback: PlaceVideoPlayback) { self.playback = playback }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !isInvalidated, message.frameInfo.isMainFrame,
                  let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
            playback.receive(event: event, code: body["code"] as? Int)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            guard !isInvalidated else { return }
            playback.fail("The video player stopped. Tap Try again to reload it.")
        }
        private func failed(_ error: Error) {
            guard !isInvalidated, (error as NSError).code != NSURLErrorCancelled else { return }
            playback.fail("The video couldn’t connect. Check your connection and try again.")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if action.navigationType == .linkActivated, let url = action.request.url,
               ["https", "http"].contains(url.scheme ?? "") { UIApplication.shared.open(url) }
            return nil
        }
    }
}
