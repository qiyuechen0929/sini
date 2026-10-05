package com.sini.sini

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 极小的原生能力桥：目前只提供 `openUrl`（用系统浏览器/对应 App 打开外链）。
 *
 * 为什么手写而不用 url_launcher：这台构建机外网不通、拉不到新包。而这个需求
 * 只要几行原生代码就够了，引一个插件反而是负担。
 */
class MainActivity : FlutterActivity() {
    private val channel = "sini/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addCategory(Intent.CATEGORY_BROWSABLE)
                                startActivity(intent)
                                result.success(null)
                            } catch (e: Exception) {
                                // 没有能打开这个链接的应用：回给 Dart 去降级处理
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
