class MegaWatchTvChannelRecord {
  final String channelId;
  final String name;
  final List<String> keywords;
  final bool avoidNsfw;
  final int channelNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MegaWatchTvChannelRecord({
    required this.channelId,
    required this.name,
    required this.keywords,
    required this.avoidNsfw,
    required this.channelNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  MegaWatchTvChannelRecord copyWith({
    String? name,
    List<String>? keywords,
    bool? avoidNsfw,
    int? channelNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MegaWatchTvChannelRecord(
      channelId: channelId,
      name: name ?? this.name,
      keywords: keywords ?? this.keywords,
      avoidNsfw: avoidNsfw ?? this.avoidNsfw,
      channelNumber: channelNumber ?? this.channelNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
