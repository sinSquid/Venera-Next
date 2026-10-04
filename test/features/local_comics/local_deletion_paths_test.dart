import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/local_comics/local_deletion_paths.dart';

void main() {
  test('deletion paths remove native dot aliases and preserve SAF URIs', () {
    final root = p.absolute('fixture');
    final free = p.join(root, 'free');
    const saf = 'android://storage/Books/Comic';
    expect(
      localDirectoriesToDelete(
        libraryPath: p.join(root, 'library'),
        candidates: ['$free/.', saf],
        retained: [],
      ),
      [free, saf],
    );
  });

  test(
    'preserves overlapping references and library ancestors with normalized aliases',
    () {
      final root = p.absolute('fixture');
      String path(String part) => p.join(root, part);
      expect(
        localDirectoriesToDelete(
          libraryPath: path('library'),
          candidates: [
            root,
            path('library'),
            path('shared'),
            path('parent'),
            path('child/a'),
            path('free'),
            path('free/../free'),
          ],
          retained: [path('shared/.'), path('parent/book'), path('child')],
        ),
        [path('free')],
      );
    },
  );
}
