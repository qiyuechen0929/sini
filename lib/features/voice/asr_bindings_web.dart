/// Web 专属：把 sherpa-onnx 的 `OfflineRecognizer` 显式挂到 `globalThis`。
///
/// 背景（踩过的坑）：sherpa 包用「间接 eval」加载 `sherpa-onnx-asr.js`。按 JS 规范，
/// eval 代码里的 class/let/const 声明落在 eval 自己的词法环境里，eval 一结束就被
/// 整个丢弃（只有 function/var 会挂到 globalThis）。所以 `OfflineRecognizer`
/// （class 声明）在包加载完成后已不存在于任何可访问的作用域 —— 必须自己重新取
/// 源码，在**同一次** eval 里于末尾把它挂到 globalThis 上。
///
/// 实现说明：整段 fetch/eval 逻辑下沉为一段自包含 JS（已在真实浏览器验证），
/// Dart 只 eval 这个 async IIFE 并 await 它的 Promise —— 避免在 Dart 侧拆
/// fetch/Response/text 的 js_interop 链路（release 压缩下类型转换易踩坑）。
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// 幂等：已经挂过就直接返回。
Future<void> exposeExtraBindings() async {
  final existing = globalContext.getProperty('OfflineRecognizer'.toJS);
  if (existing != null && !existing.isUndefinedOrNull) return;

  const js = r'''
(async () => {
  const r = await fetch('assets/packages/sherpa_onnx_web/assets/sherpa-onnx-asr.js');
  if (!r.ok) throw new Error('fetch asr.js failed: ' + r.status);
  const t = await r.text();
  (0, eval)(t + '\n;globalThis.OfflineRecognizer = OfflineRecognizer;' +
    'globalThis.createOnlineRecognizer = createOnlineRecognizer;');
  return typeof globalThis.OfflineRecognizer;
})()
''';
  final evalFn = globalContext.getProperty('eval'.toJS) as JSFunction;
  final result = evalFn.callAsFunction(null, js.toJS);
  await (result as JSPromise).toDart;
}
