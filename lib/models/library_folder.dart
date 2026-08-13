class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  LibraryFolder copyWith({String? name}) {
    return LibraryFolder(id: id, name: name ?? this.name, createdAt: createdAt);
  }

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LibraryFolder.fromJson(Map<String, dynamic> json) {
    return LibraryFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
