import 'dart:isolate';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/services.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_saf/flutter_saf.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:share_plus/share_plus.dart' as s;
import 'package:venera_next/foundation/file_type.dart';

export 'dart:io';
export 'dart:typed_data';
export 'package:venera_next/foundation/file_system.dart';

class IO {
  /// A global flag used to indicate whether the app is selecting files.
  ///
  /// Select file and other similar file operations will launch external programs,
  /// causing the app to lose focus. AppLifecycleState will be set to paused.
  static bool get isSelectingFiles => _activeSelections > 0;

  static int _activeSelections = 0;

  static void _beginSelection() => _activeSelections++;

  static void _endSelection() {
    // Keep the short focus-return grace period for each operation. An earlier
    // picker finishing must not reset the state of another active picker.
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      _activeSelections--;
    });
  }
}

/// Copy the **contents** of the source directory to the destination directory.
/// This function is executed in an isolate to prevent the UI from freezing.
Future<void> copyDirectoryIsolate(
  Directory source,
  Directory destination,
) async {
  await Isolate.run(() => overrideIO(() => copyDirectory(source, destination)));
}

class DirectoryPicker {
  /// Pick a directory.
  ///
  /// The directory may not be usable after the instance is GCed.
  DirectoryPicker();

  static final _finalizer = Finalizer<String>((path) {
    if (path.startsWith(App.cachePath)) {
      Directory(path).deleteIgnoreError();
    }
    if (App.isIOS) {
      _methodChannel.invokeMethod("stopAccessingSecurityScopedResource");
    }
  });

  static const _methodChannel = MethodChannel("venera/method_channel");

  Future<Directory?> pickDirectory({bool directAccess = false}) async {
    IO._beginSelection();
    try {
      String? directory;
      if (App.isDesktop) {
        directory = await file_selector.getDirectoryPath();
      } else if (App.isAndroid) {
        directory = (await AndroidDirectory.pickDirectory())?.path;
        if (directory != null && directAccess) {
          // Native library does not have access to the directory. Copy it to cache.
          var cache = FilePath.join(App.cachePath, "selected_directory");
          if (Directory(cache).existsSync()) {
            Directory(cache).deleteSync(recursive: true);
          }
          Directory(cache).createSync();
          await copyDirectoryIsolate(Directory(directory), Directory(cache));
          directory = cache;
        }
      } else {
        // iOS uses a security-scoped directory owned by the native picker.
        directory = await _methodChannel.invokeMethod<String?>(
          "getDirectoryPath",
        );
      }
      if (directory == null) return null;
      _finalizer.attach(this, directory);
      return Directory(directory);
    } finally {
      IO._endSelection();
    }
  }
}

class IOSDirectoryPicker {
  static const MethodChannel _channel = MethodChannel("venera/method_channel");

  // 调用 iOS 目录选择方法
  static Future<String?> selectDirectory() async {
    IO._beginSelection();
    try {
      final String? path = await _channel.invokeMethod('selectDirectory');
      return path;
    } finally {
      IO._endSelection();
    }
  }
}

Future<FileSelectResult?> selectFile({required List<String> ext}) async {
  IO._beginSelection();
  try {
    var extensions = App.isMacOS || App.isIOS ? null : ext;
    file_selector.XTypeGroup typeGroup = file_selector.XTypeGroup(
      label: 'files',
      extensions: extensions,
    );
    FileSelectResult? file;
    if (App.isAndroid) {
      const selectFileChannel = MethodChannel("venera/select_file");
      String mimeType = "*/*";
      if (ext.length == 1) {
        mimeType = FileType.fromExtension(ext[0]).mime;
        if (mimeType == "application/octet-stream") {
          mimeType = "*/*";
        }
      }
      var filePath = await selectFileChannel.invokeMethod(
        "selectFile",
        mimeType,
      );
      if (filePath == null) return null;
      file = FileSelectResult(filePath);
    } else {
      var xFile = await file_selector.openFile(
        acceptedTypeGroups: <file_selector.XTypeGroup>[typeGroup],
      );
      if (xFile == null) return null;
      file = FileSelectResult(xFile.path);
    }
    if (!ext.contains(file.path.split(".").last)) {
      if (!App.rootContext.mounted) return null;
      App.rootContext.showMessage(
        message: "Invalid file type: ${file.path.split(".").last}",
      );
      return null;
    }
    return file;
  } finally {
    IO._endSelection();
  }
}

Future<List<FileSelection>> selectFiles({
  required List<String> ext,
  List<String>? uniformTypeIdentifiers,
}) async {
  IO._beginSelection();
  try {
    if (App.isAndroid) {
      final mimeType = ext.length == 1
          ? FileType.fromExtension(ext.single).mime
          : '*/*';
      final files = await FileSelection._channel.invokeListMethod<dynamic>(
        'selectFiles',
        mimeType == 'application/octet-stream' ? '*/*' : mimeType,
      );
      return [
        for (final file in files ?? const [])
          FileSelection.androidDocument(
            uri: file['uri'] as String,
            name: file['name'] as String,
          ),
      ];
    }
    final files = await file_selector.openFiles(
      acceptedTypeGroups: [
        file_selector.XTypeGroup(
          label: 'files',
          extensions: App.isIOS || App.isMacOS ? null : ext,
          uniformTypeIdentifiers: uniformTypeIdentifiers,
        ),
      ],
    );
    return files.map((file) => FileSelection(file.path)).toList();
  } finally {
    IO._endSelection();
  }
}

/// A selection that keeps its file alive until explicitly released.
/// Android document URIs are copied only when the consumer needs the file.
class FileSelection {
  FileSelection(String path)
    : identifier = path,
      name = File(path).name,
      _file = File(path);

  FileSelection.androidDocument({required String uri, required this.name})
    : identifier = uri;

  static const _channel = MethodChannel('venera/select_file');

  final String identifier;
  final String name;
  // Explicit disposal owns only native copies. Avoid the legacy selection's
  // path-based GC cleanup, which can mistake caller-owned cache files for copies.
  File? _file;
  String? _temporaryPath;
  bool _disposed = false;
  Future<File>? _preparing;
  Future<void>? _disposing;

  Future<File> prepare() async {
    if (_disposed) throw StateError('File selection has been released');
    if (_file != null) return _file!;
    final preparing = _preparing ??= _prepareDocument();
    try {
      final file = await preparing;
      if (_disposed) throw StateError('File selection has been released');
      return file;
    } finally {
      if (identical(_preparing, preparing)) _preparing = null;
    }
  }

  Future<File> _prepareDocument() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'prepareFile',
      identifier,
    );
    if (result == null) throw StateError('Failed to prepare selected file');
    final path = result['path'] as String;
    if (result['temporary'] == true) _temporaryPath = path;
    return _file = File(path);
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    // Preparation may still be copying a document. Wait for its path so that
    // disposal also owns and releases temporary files returned after cancellation.
    try {
      await _preparing;
    } catch (_) {
      // The prepare caller receives this failure; no temporary file was returned.
    }
    try {
      if (_temporaryPath != null) {
        await _channel.invokeMethod<void>('releaseFile', _temporaryPath);
      }
    } finally {
      _file = null;
      _temporaryPath = null;
    }
  }
}

Future<String?> selectDirectory() async {
  IO._beginSelection();
  try {
    var path = await file_selector.getDirectoryPath();
    return path;
  } finally {
    IO._endSelection();
  }
}

// selectDirectoryIOS
Future<String?> selectDirectoryIOS() async {
  return IOSDirectoryPicker.selectDirectory();
}

/// Returns `true` if the file was saved, `false` if the user cancelled.
Future<bool> saveFile({
  Uint8List? data,
  required String filename,
  File? file,
}) async {
  if (data == null && file == null) {
    throw Exception("data and file cannot be null at the same time");
  }
  filename = sanitizeFileName(filename);
  IO._beginSelection();
  Directory? temporaryDirectory;
  try {
    if (data != null || App.isIOS) {
      temporaryDirectory = await Directory(
        App.cachePath,
      ).createTemp('file-export-');
      final exportFile = File(FilePath.join(temporaryDirectory.path, filename));
      if (data != null) {
        await exportFile.writeAsBytes(data);
      } else {
        await file!.copy(exportFile.path);
      }
      file = exportFile;
    }
    if (App.isMobile) {
      // iOS uses the source basename. Passing fileName makes the plugin copy to
      // a shared temporary path, which can overwrite another export or source.
      final params = SaveFileDialogParams(sourceFilePath: file!.path);
      final result = await FlutterFileDialog.saveFile(params: params);
      return result != null;
    } else {
      final result = await file_selector.getSaveLocation(
        suggestedName: filename,
      );
      if (result != null) {
        var xFile = file_selector.XFile(file!.path);
        await xFile.saveTo(result.path);
        return true;
      }
      return false;
    }
  } finally {
    await temporaryDirectory?.deleteIgnoreError(recursive: true);
    IO._endSelection();
  }
}

final class _IOOverrides extends IOOverrides {
  @override
  Directory createDirectory(String path) {
    if (App.isAndroid) {
      var dir = AndroidDirectory.fromPathSync(path);
      if (dir == null) {
        return super.createDirectory(path);
      }
      return dir;
    } else {
      return super.createDirectory(path);
    }
  }

  @override
  File createFile(String path) {
    if (path.startsWith("file:")) {
      path = Uri.parse(path).toFilePath();
    }
    if (App.isAndroid) {
      var f = AndroidFile.fromPathSync(path);
      if (f == null) {
        return super.createFile(path);
      }
      return f;
    } else {
      return super.createFile(path);
    }
  }
}

T overrideIO<T>(T Function() f) {
  return IOOverrides.runWithIOOverrides<T>(f, _IOOverrides());
}

class Share {
  static void shareFile({
    required Uint8List data,
    required String filename,
    required String mime,
  }) {
    if (!App.isWindows) {
      s.SharePlus.instance.share(
        s.ShareParams(
          files: [s.XFile.fromData(data, mimeType: mime)],
          fileNameOverrides: [filename],
        ),
      );
    } else {
      // write to cache
      var file = File(FilePath.join(App.cachePath, filename));
      file.writeAsBytesSync(data);
      s.SharePlus.instance.share(s.ShareParams(files: [s.XFile(file.path)]));
    }
  }

  static void shareText(String text) {
    s.SharePlus.instance.share(s.ShareParams(text: text));
  }
}

class FileSelectResult {
  final String path;

  static final _finalizer = Finalizer<String>((path) {
    if (path.startsWith(App.cachePath)) {
      File(path).deleteIgnoreError();
    }
  });

  FileSelectResult(this.path) {
    _finalizer.attach(this, path);
  }

  Future<void> saveTo(String path) async {
    await File(this.path).copy(path);
  }

  Future<Uint8List> readAsBytes() {
    return File(path).readAsBytes();
  }

  String get name => File(path).name;
}
