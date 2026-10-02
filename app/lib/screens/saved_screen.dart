import 'package:flutter/material.dart';

import '../data/timestamp_format.dart';
import '../models/news_article.dart';
import '../theme/app_theme.dart';
import 'article_web_view_screen.dart';

/// Keeps its own copy of the list for immediate UI; the callbacks sync
/// HomeScreen's state (and the store) with every remove/undo.
class SavedScreen extends StatefulWidget {
  final List<NewsArticle> initialSaved;
  final void Function(NewsArticle) onRemove;
  final void Function(NewsArticle, int index) onRestore;
  final ImageProvider Function(String url) imageProviderBuilder;

  SavedScreen({
    super.key,
    required this.initialSaved,
    required this.onRemove,
    required this.onRestore,
    ImageProvider Function(String url)? imageProviderBuilder,
  }) : imageProviderBuilder =
           imageProviderBuilder ?? ((url) => NetworkImage(url));

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late final List<NewsArticle> _saved = [...widget.initialSaved];

  void _remove(NewsArticle a) {
    final index = _saved.indexWhere((s) => s.id == a.id);
    if (index < 0) return;
    setState(() => _saved.removeAt(index));
    widget.onRemove(a);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 2500),
          persist: false,
          content: Row(
            children: [
              Icon(Icons.bookmark_remove_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 12),
              const Text('Removed from saved'),
            ],
          ),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              setState(() => _saved.insert(index.clamp(0, _saved.length), a));
              widget.onRestore(a, index);
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Saved'),
      ),
      body: _saved.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No saved news yet',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Tap the bookmark on a card to save it',
                    style: TextStyle(color: AppColors.textTertiary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _saved.length,
              itemBuilder: (context, i) {
                final a = _saved[i];
                return Dismissible(
                  key: ValueKey(a.id),
                  onDismissed: (_) => _remove(a),
                  child: _SavedRow(
                    article: a,
                    imageProvider: widget.imageProviderBuilder(a.imageUrl),
                    onRemove: () => _remove(a),
                  ),
                );
              },
            ),
    );
  }
}

class _SavedRow extends StatelessWidget {
  final NewsArticle article;
  final ImageProvider imageProvider;
  final VoidCallback onRemove;

  const _SavedRow({
    required this.article,
    required this.imageProvider,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final time = article.publishedAt == null
        ? null
        : formatPublishedAt(article.publishedAt!, article.language);
    return ListTile(
      tileColor: AppColors.background,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ArticleWebViewScreen(articleUrl: article.articleUrl),
        ),
      ),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image(
          image: imageProvider,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
            width: 64,
            height: 64,
            child: Icon(
              Icons.broken_image_outlined,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ),
      title: Text(
        article.headline,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      subtitle: Text(
        time == null ? article.source : '${article.source} · $time',
        style: const TextStyle(color: AppColors.textTertiary),
      ),
      trailing: IconButton(
        tooltip: 'Remove',
        onPressed: onRemove,
        icon: const Icon(Icons.bookmark, color: AppColors.accent),
      ),
    );
  }
}
