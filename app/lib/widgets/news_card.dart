import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/timestamp_format.dart';
import '../models/news_article.dart';
import '../theme/app_theme.dart';

class NewsCard extends StatelessWidget {
  final NewsArticle article;
  final ImageProvider Function(String url) imageProviderBuilder;

  NewsCard({
    super.key,
    required this.article,
    ImageProvider Function(String url)? imageProviderBuilder,
  }) : imageProviderBuilder =
           imageProviderBuilder ?? ((url) => NetworkImage(url));

  // --- Style constants for the head block (source pill, headline, ---
  // --- timestamp row) and the snippet/"Read more" block below it.  ---

  static const _pillFontSize = 12.0;
  static const _pillVerticalPadding = 4.0; // EdgeInsets.symmetric(vertical: 4)
  static const _headlineFontSize = 22.0;
  static const _timestampFontSize = 12.0;
  static const _timestampIconSize = 12.0;
  static const _snippetFontSize = 15.0;

  // Approximate default line-height (Flutter/Material text has no explicit
  // `height` set on these styles, so its rendered line height is roughly
  // 1.2x the font size for the ambient font). Used only to turn the pill's
  // and timestamp row's known font sizes/padding into a height estimate
  // without a second TextPainter pass.
  static const _kLineHeightFactor = 1.2;

  static const _pillHeight =
      _pillFontSize * _kLineHeightFactor + _pillVerticalPadding * 2;
  static const _timestampRowHeight = _timestampFontSize * _kLineHeightFactor;

  static const _pillTextStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: _pillFontSize,
  );
  static const _headlineTextStyle = TextStyle(
    color: AppColors.textPrimary,
    fontSize: _headlineFontSize,
    fontWeight: FontWeight.bold,
  );
  static const _timestampTextStyle = TextStyle(
    color: AppColors.textTertiary,
    fontSize: _timestampFontSize,
  );
  static const _snippetTextStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: _snippetFontSize,
  );
  static const _readMoreTextStyle = TextStyle(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w600,
  );

  static const _kOuterPadding = EdgeInsets.all(20);
  static const _kMinSnippetLines = 2;

  @override
  Widget build(BuildContext context) {
    final imageProvider = imageProviderBuilder(article.imageUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        // A blurred, darkened, cropped copy of the same photo behind the
        // whole card: the sharp image above fully covers it where the two
        // overlap, but it also fills whatever leftover space the sharp,
        // uncropped image (below) doesn't reach — so that space reads as
        // an intentional backdrop instead of dead black space.
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Image(
              image: imageProvider,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.55)),
        LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  // The image box is sized to the photo's own aspect ratio
                  // (no crop, no letterbox bars); this cap only guards
                  // against a pathological very-tall image pushing the
                  // text block off screen, leaving it a reliable minimum
                  // share.
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.65,
                  ),
                  child: _AutoAspectImage(
                    imageProvider: imageProvider,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade800,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textTertiary,
                        size: 64,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, textConstraints) =>
                        _buildTextArea(context, textConstraints),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // Builds the always-visible head block (source pill, headline, optional
  // timestamp row) followed by the snippet/"Read more" block, which is
  // either plain flowing text (if it fits) or a small, tightly-bounded
  // scrollable region (if it doesn't) — see `_buildSnippetBlock`.
  //
  // Nothing here is wrapped in an outer scrollable: the head block must
  // never be truncated or scrollable, and only the snippet block itself is
  // allowed to scroll, so a vertical swipe anywhere else on the card is
  // free to reach the outer feed's PageView.
  Widget _buildTextArea(BuildContext context, BoxConstraints textConstraints) {
    final textScaler = MediaQuery.textScalerOf(context);
    final availableWidth =
        textConstraints.maxWidth - _kOuterPadding.horizontal;
    final hasTimestamp = article.publishedAt != null;

    final headlineHeight = _measureHeight(
      text: article.headline,
      style: _headlineTextStyle,
      maxWidth: availableWidth,
      textScaler: textScaler,
    );

    var headBlockHeight = _pillHeight + 10 + headlineHeight;
    if (hasTimestamp) {
      headBlockHeight += 6 + _timestampRowHeight;
    }
    headBlockHeight += 8; // spacing before the snippet block

    final availableForSnippetBlock =
        textConstraints.maxHeight - _kOuterPadding.vertical - headBlockHeight;

    return Padding(
      padding: _kOuterPadding,
      // OverflowBox hands the Column an unbounded max height, so in the
      // pathological case where the head block's natural, uncapped height
      // (e.g. an extremely long, unbroken headline) exceeds what's
      // actually available, the Column simply sizes to its content instead
      // of hitting a RenderFlex overflow assertion. The head block still
      // renders in full (no maxLines/ellipsis) and is never wrapped in a
      // scrollable — in this rare case the content bleeds past its
      // allotted area rather than being clipped, scrolled, or truncated.
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minHeight: 0,
        maxHeight: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._buildHeadBlock(hasTimestamp),
            _buildSnippetBlock(
              context: context,
              availableWidth: availableWidth,
              availableHeight: availableForSnippetBlock,
              textScaler: textScaler,
            ),
          ],
        ),
      ),
    );
  }

  // The source pill, headline, and (if present) the timestamp row: fixed,
  // never-scrollable, never-truncated content.
  List<Widget> _buildHeadBlock(bool hasTimestamp) {
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(article.source, style: _pillTextStyle),
      ),
      const SizedBox(height: 10),
      Text(article.headline, style: _headlineTextStyle),
      if (hasTimestamp) ...[
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time,
              size: _timestampIconSize,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              formatPublishedAt(article.publishedAt!, article.language),
              style: _timestampTextStyle,
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
    ];
  }

  // Measures whether the full snippet text fits in the space left after the
  // head block. If it does, it (and "Read more →") render as plain,
  // non-scrolling flow. If not, only this small region becomes scrollable,
  // clamped to a sensible minimum height so it can't be crushed to near
  // nothing by an unusually long headline.
  Widget _buildSnippetBlock({
    required BuildContext context,
    required double availableWidth,
    required double availableHeight,
    required TextScaler textScaler,
  }) {
    final readMoreHeight = _measureHeight(
      text: 'Read more →',
      style: _readMoreTextStyle,
      maxWidth: availableWidth,
      textScaler: textScaler,
    );
    final availableForSnippetOnly = availableHeight - 10 - readMoreHeight;

    final snippetFullHeight = _measureHeight(
      text: article.snippet,
      style: _snippetTextStyle,
      maxWidth: availableWidth,
      textScaler: textScaler,
    );

    final snippetAndReadMore = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(article.snippet, style: _snippetTextStyle),
        const SizedBox(height: 10),
        const Text('Read more →', style: _readMoreTextStyle),
      ],
    );

    if (snippetFullHeight <= availableForSnippetOnly) {
      return snippetAndReadMore;
    }

    // Doesn't fit: confine scrolling to this block only. Never clamp below
    // roughly two lines of snippet text plus the "Read more →" row, so a
    // long headline can't crush this region to near-zero.
    final minSnippetTextHeight = _measureHeight(
      text: article.snippet,
      style: _snippetTextStyle,
      maxWidth: availableWidth,
      textScaler: textScaler,
      maxLines: _kMinSnippetLines,
    );
    final minBlockHeight = minSnippetTextHeight + 10 + readMoreHeight;
    final clampedHeight = availableHeight < minBlockHeight
        ? minBlockHeight
        : availableHeight;

    return SizedBox(
      height: clampedHeight,
      child: SingleChildScrollView(child: snippetAndReadMore),
    );
  }

  double _measureHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextScaler textScaler,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth > 0 ? maxWidth : 0);
    return painter.height;
  }
}

// Sizes its box to the resolved image's own aspect ratio, so the photo never
// needs cropping (BoxFit.cover) or letterbox bars (a fixed box with
// BoxFit.contain) — it just gets exactly the height its width implies.
class _AutoAspectImage extends StatefulWidget {
  final ImageProvider imageProvider;
  final Widget Function(BuildContext, Object, StackTrace?) errorBuilder;

  const _AutoAspectImage({
    required this.imageProvider,
    required this.errorBuilder,
  });

  @override
  State<_AutoAspectImage> createState() => _AutoAspectImageState();
}

class _AutoAspectImageState extends State<_AutoAspectImage> {
  double? _aspectRatio;
  ImageStream? _stream;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener(_onImage);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveStream();
  }

  @override
  void didUpdateWidget(_AutoAspectImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageProvider != oldWidget.imageProvider) {
      _aspectRatio = null;
      _resolveStream();
    }
  }

  void _resolveStream() {
    final newStream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (newStream.key != _stream?.key) {
      _stream?.removeListener(_listener);
      _stream = newStream;
      _stream!.addListener(_listener);
    }
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final ratio = info.image.width / info.image.height;
    if (mounted && ratio != _aspectRatio) {
      setState(() => _aspectRatio = ratio);
    }
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // 16:9 default keeps layout stable before the real size resolves.
      aspectRatio: _aspectRatio ?? 16 / 9,
      child: Image(
        image: widget.imageProvider,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: widget.errorBuilder,
      ),
    );
  }
}
