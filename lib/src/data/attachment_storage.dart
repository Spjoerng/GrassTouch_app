import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Database records store relative paths for future portable backups.
class AttachmentStorage {
  AttachmentStorage(this.root);
  final Directory root;
  static Future<AttachmentStorage> open() async {
    final root = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'attachments'),
    );
    await root.create(recursive: true);
    return AttachmentStorage(root);
  }

  File resolve(String relativePath) {
    final target = p.normalize(p.join(root.absolute.path, relativePath));
    if (p.isAbsolute(relativePath) || !p.isWithin(root.absolute.path, target)) {
      throw ArgumentError('Invalid attachment path');
    }
    return File(target);
  }

  Future<String> importFile(File source) async {
    await root.create(recursive: true);
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(1 << 32)}${p.extension(source.path)}';
    try {
      await source.copy(resolve(name).path);
    } catch (_) {
      await delete(name);
      rethrow;
    }
    return name;
  }

  Future<void> delete(String relativePath) async {
    final file = resolve(relativePath);
    if (await file.exists()) await file.delete();
  }
}
