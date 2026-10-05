/// IndexedDB 实现（Web 专用，条件导入）。
///
/// Dart 3 的 dart:indexed_db 已 promise 化：open/put/getObject 直接返回
/// Future，不需要再手写 onSuccess/onError 事件监听。
library;

import 'dart:html' as html;
import 'dart:indexed_db' as idb;
import 'dart:typed_data';

const String _dbName = 'sini_voice';
const String _storeName = 'ref_audio';

idb.Database? _db;

Future<idb.Database> _open() async {
  if (_db != null) return _db!;
  final db = await html.window.indexedDB!.open(_dbName, version: 1,
      onUpgradeNeeded: (e) {
    final db = e.target.result as idb.Database;
    if (!db.objectStoreNames!.contains(_storeName)) {
      db.createObjectStore(_storeName);
    }
  });
  return _db = db;
}

Future<void> save(String personaId, Uint8List wavBytes) async {
  final db = await _open();
  await db
      .transaction(_storeName, 'readwrite')
      .objectStore(_storeName)
      .put(wavBytes, personaId);
}

Future<Uint8List?> load(String personaId) async {
  final db = await _open();
  final v = await db
      .transaction(_storeName, 'readonly')
      .objectStore(_storeName)
      .getObject(personaId);
  return v is Uint8List ? v : null;
}

Future<void> delete(String personaId) async {
  final db = await _open();
  await db
      .transaction(_storeName, 'readwrite')
      .objectStore(_storeName)
      .delete(personaId);
}
