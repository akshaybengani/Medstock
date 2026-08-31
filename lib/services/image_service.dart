import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Picks a medicine photo and keeps a private copy inside the app's documents
/// directory. The picker hands back a cache path that the OS may reclaim, so
/// copying is what makes the image survive a restart.
class ImageService {
  ImageService._();
  static final ImageService instance = ImageService._();

  final ImagePicker _picker = ImagePicker();

  static const String _folder = 'medicine_images';

  Future<String?> pick({required bool fromCamera}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 82,
    );
    if (picked == null) return null;
    return _persist(File(picked.path));
  }

  Future<String> _persist(File source) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _folder));
    if (!await dir.exists()) await dir.create(recursive: true);

    final ext = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final name = 'med_${DateTime.now().microsecondsSinceEpoch}$ext';
    final target = p.join(dir.path, name);

    await source.copy(target);
    return target;
  }

  /// Best-effort cleanup when an image is replaced or a medicine deleted.
  Future<void> deleteIfOwned(String? path) async {
    if (path == null || !path.contains(_folder)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A stale image file is harmless — never fail a save over it.
    }
  }
}
