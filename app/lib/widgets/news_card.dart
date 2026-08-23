import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/timestamp_format.dart';
import '../models/news_article.dart';

class NewsCard extends StatelessWidget {
  final NewsArticle article;
  final ImageProvider Function(String url) imageProviderBuilder;

  NewsCard({
    super.key,
    required this.article,
    ImageProvider Function(String url)? imageProviderBuilder,
  }) : imageProviderBuilder =
           imageProviderBuilder ?? ((url) => NetworkImage(url));

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
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  // A LayoutBuilder-fed minHeight keeps short content
                  // vertically centered (the old Align's job), while
                  // SingleChildScrollView lets a headline long enough to
                  // overflow the available space scroll instead of being
                  // clipped or truncated.
                  child: LayoutBuilder(
                    builder: (context, textConstraints) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: textConstraints.maxHeight,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    article.source,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  article.headline,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (article.publishedAt != null) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        size: 12,
                                        color: Colors.white54,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        formatPublishedAt(
                                          article.publishedAt!,
                                          article.language,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  article.snippet,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Read more →',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
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
