class NewsArticle {
  final String id;
  final String category;
  final String source;
  final String headline;
  final String snippet;
  final String imageUrl;
  final String articleUrl;
  final String language;
  final DateTime? publishedAt;

  const NewsArticle({
    required this.id,
    required this.category,
    required this.source,
    required this.headline,
    required this.snippet,
    required this.imageUrl,
    required this.articleUrl,
    this.language = 'en',
    this.publishedAt,
  });

  /// Throws (TypeError) on a missing/mistyped required field; callers that
  /// read untrusted lists catch and skip.
  factory NewsArticle.fromJson(Map<String, dynamic> map) {
    final publishedAt = map['publishedAt'];
    return NewsArticle(
      id: map['id'] as String,
      category: map['category'] as String,
      source: map['source'] as String,
      headline: map['headline'] as String,
      snippet: (map['snippet'] as String?) ?? '',
      imageUrl: map['imageUrl'] as String,
      articleUrl: map['articleUrl'] as String,
      language: map['language'] is String ? map['language'] as String : 'en',
      publishedAt: publishedAt is String ? DateTime.tryParse(publishedAt) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'source': source,
    'headline': headline,
    'snippet': snippet,
    'imageUrl': imageUrl,
    'articleUrl': articleUrl,
    'language': language,
    'publishedAt': publishedAt?.toIso8601String(),
  };
}
