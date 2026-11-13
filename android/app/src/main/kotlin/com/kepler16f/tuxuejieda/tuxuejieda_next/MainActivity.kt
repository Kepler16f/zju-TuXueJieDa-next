package com.kepler16f.tuxuejieda.tuxuejieda_next

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.kepler16f.tuxuejieda/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSupportedAbis" -> {
                        result.success(Build.SUPPORTED_ABIS.toList())
                    }
                    "installApk" -> {
                        val apkPath = call.argument<String>("path")
                        if (apkPath.isNullOrEmpty()) {
                            result.error("INVALID_PATH", "APK path is empty", null)
                            return@setMethodCallHandler
                        }
                        result.success(launchApkInstaller(File(apkPath)))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun launchApkInstaller(apkFile: File): String {
        if (!apkFile.exists()) {
            return "未找到安装包文件：${apkFile.absolutePath}"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            val permIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(permIntent)
            return "请在系统设置中允许安装未知来源应用后，再次点击“立即安装”。"
        }

        val apkUri: Uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(apkUri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(installIntent)
        return "已调用系统安装器打开 ${apkFile.name}。"
    }
}
