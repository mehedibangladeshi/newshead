import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

// Universal-dark-mode style CSS filter: inverts the whole page, then
// re-inverts photo/video content so it doesn't end up looking like a
// negative. Two exclusions, found by inspecting real article pages:
//  - Images inside <header>/<nav> (site logos, brand marks) are NOT
//    re-inverted: a logo's true colors are usually dark-on-light, so
//    restoring them clashes with the header's own now-inverted (dark)
//    background. Left single-inverted, they behave like the rest of the
//    page's text and stay readable against the dark header.
//  - Elements with an inline `background-image` style (blur-up/placeholder
//    wrappers some sites put behind a lazy-loaded <img>) are re-inverted
//    too, otherwise the placeholder shows through in the wrong colors
//    while loading or at the image's edges.
const String _darkModeInjectionScript = r'''
(function() {
  if (document.getElementById('newshead-dark-mode')) { return; }
  var style = document.createElement('style');
  style.id = 'newshead-dark-mode';
  style.textContent =
    'html { filter: invert(1) hue-rotate(180deg) !important; background: #fff !important; }' +
    'img:not(header img):not(nav img), video, picture, iframe, svg, canvas, embed, [style*="background-image"] { filter: invert(1) hue-rotate(180deg) !important; }';
  document.head.appendChild(style);
})();
''';

class ArticleWebViewScreen extends StatefulWidget {
  final String articleUrl;

  const ArticleWebViewScreen({super.key, required this.articleUrl});

  @override
  State<ArticleWebViewScreen> createState() => _ArticleWebViewScreenState();
}

class _ArticleWebViewScreenState extends State<ArticleWebViewScreen> {
  late final WebViewController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) =>
              _controller.runJavaScript(_darkModeInjectionScript),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? true) {
              setState(() => _hasError = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.articleUrl));
  }

  void _retry() {
    setState(() => _hasError = false);
    _controller.loadRequest(Uri.parse(widget.articleUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: _hasError
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Couldn\'t load this article.'),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
