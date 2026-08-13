import 'package:flutter_test/flutter_test.dart';
import 'package:panelly/models/library_folder.dart';

void main() {
  test('LibraryFolder JSON round-trip keeps identity and name', () {
    final folder = LibraryFolder(
      id: 'folder-1',
      name: '收藏',
      createdAt: DateTime.utc(2026, 8, 13),
    );

    final restored = LibraryFolder.fromJson(folder.toJson());

    expect(restored.id, folder.id);
    expect(restored.name, '收藏');
    expect(restored.createdAt, folder.createdAt);
  });
}
