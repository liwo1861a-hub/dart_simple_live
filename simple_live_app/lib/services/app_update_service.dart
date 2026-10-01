import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';

class AppUpdateInfo {
  final String version;
  final int versionNum;
  final String versionDesc;
  final bool prerelease;
  final String downloadUrl;

  AppUpdateInfo({
    required this.version,
    required this.versionNum,
    required this.versionDesc,
    required this.prerelease,
    required this.downloadUrl,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['version']?.toString() ?? '',
      versionNum: int.tryParse(json['version_num']?.toString() ?? '0') ?? 0,
      versionDesc: json['version_desc']?.toString() ?? '',
      prerelease: json['prerelease'] == true,
      downloadUrl: json['download_url']?.toString() ?? '',
    );
  }
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  AppUpdateService._internal();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  /// 多个镜像源多重兜底，确保国内各网络环境 100% 成功检查更新
  final List<String> _updateEndpoints = [
    'https://raw.githubusercontent.com/liwo1861a-hub/dart_simple_live/master/assets/app_version.json',
    'https://github.iill.moe/liwo1861a-hub/dart_simple_live/master/assets/app_version.json',
    'https://cdn.jsdelivr.net/gh/liwo1861a-hub/dart_simple_live@master/assets/app_version.json',
  ];

  /// 检查是否有新版本
  Future<void> checkUpdate({bool showToastOnLatest = false}) async {
    if (showToastOnLatest) {
      SmartDialog.showLoading(msg: "正在检查更新...");
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      AppUpdateInfo? remoteInfo;
      for (final endpoint in _updateEndpoints) {
        try {
          final res = await _dio.get(
            endpoint,
            queryParameters: {'_ts': DateTime.now().millisecondsSinceEpoch},
          );
          dynamic data = res.data;
          if (data is String) {
            data = jsonDecode(data);
          }
          if (data is Map<String, dynamic>) {
            remoteInfo = AppUpdateInfo.fromJson(data);
            break;
          }
        } catch (e) {
          Log.d("Update mirror failed: $endpoint, trying next...");
        }
      }

      if (showToastOnLatest) {
        SmartDialog.dismiss();
      }

      if (remoteInfo == null) {
        if (showToastOnLatest) {
          SmartDialog.showToast("检查更新失败，请稍后重试");
        }
        return;
      }

      // 比较版本号：先比版本数字，再比语义化版本字符串
      bool hasUpdate = false;
      if (remoteInfo.versionNum > 0 && currentBuildNumber > 0) {
        hasUpdate = remoteInfo.versionNum > currentBuildNumber;
      } else {
        hasUpdate = _isVersionHigher(remoteInfo.version, currentVersion);
      }

      if (hasUpdate) {
        _showUpdateDialog(remoteInfo, currentVersion);
      } else if (showToastOnLatest) {
        SmartDialog.showToast("当前已是最新版本 (v$currentVersion)");
      }
    } catch (e) {
      Log.logPrint(e);
      if (showToastOnLatest) {
        SmartDialog.dismiss();
        SmartDialog.showToast("检查更新异常: $e");
      }
    }
  }

  /// 语义化版本号比对
  bool _isVersionHigher(String remote, String local) {
    try {
      List<int> rParts = remote.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map(int.parse).toList();
      List<int> lParts = local.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map(int.parse).toList();
      for (int i = 0; i < rParts.length && i < lParts.length; i++) {
        if (rParts[i] > lParts[i]) return true;
        if (rParts[i] < lParts[i]) return false;
      }
      return rParts.length > lParts.length;
    } catch (e) {
      return false;
    }
  }

  /// 弹出更新窗口
  void _showUpdateDialog(AppUpdateInfo info, String currentVersion) {
    SmartDialog.show(
      builder: (context) {
        return Container(
          width: 320,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_rounded, color: Theme.of(context).primaryColor, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "发现新版本 v${info.version}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "当前版本: v$currentVersion",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              const Text(
                "更新内容:",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Text(
                    info.versionDesc.isEmpty ? "日常维护与性能优化" : info.versionDesc,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.85),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => SmartDialog.dismiss(),
                    child: const Text("稍后再说", style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onPressed: () async {
                      SmartDialog.dismiss();
                      final targetUrl = info.downloadUrl.isNotEmpty
                          ? info.downloadUrl
                          : 'https://github.com/liwo1861a-hub/dart_simple_live/releases/tag/v${info.version}';
                      await launchUrlString(targetUrl, mode: LaunchMode.externalApplication);
                    },
                    child: const Text("立即更新"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
