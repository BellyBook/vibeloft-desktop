/*
 * Purpose: 应用使用时长追踪服务，监控各应用的活跃时间
 * Inputs: 系统进程信息、活动窗口事件
 * Outputs: 应用使用统计数据、摸鱼率计算
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎应用使用追踪服务
// ═══════════════════════════════════════════════════════════════════════════

class AppUsageTracker extends ChangeNotifier {
  static final AppUsageTracker _instance = AppUsageTracker._internal();
  factory AppUsageTracker() => _instance;
  AppUsageTracker._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据存储
  // ─────────────────────────────────────────────────────────────────────────

  final Map<String, Duration> _appUsageToday = {};
  final Map<String, DateTime> _appStartTime = {};
  String? _currentApp;
  Timer? _trackingTimer;
  DateTime _dayStartTime = DateTime.now();

  // 工作应用列表（可配置）
  final Set<String> _workApps = {
    'Cursor',
    'Xcode',
    'Android Studio',
    'Visual Studio Code',
    'IntelliJ IDEA',
    'Terminal',
    'Warp',
    'iTerm',
    'Claude',
    'ChatGPT',
    'GitHub Desktop',
    'Sourcetree',
    'Postman',
    'Docker',
  };

  // 摸鱼应用列表（可配置）
  final Set<String> _slackingApps = {
    '微信',
    'WeChat',
    'QQ',
    'Twitter',
    'Instagram',
    'YouTube',
    'Bilibili',
    'Netflix',
    'Spotify',
    'Music',
    'Safari',
    'Chrome',
    'Firefox',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // ▎初始化和启动追踪
  // ─────────────────────────────────────────────────────────────────────────

  void startTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCurrentApp();
    });

    // 每天重置
    Timer.periodic(const Duration(hours: 1), (_) {
      _checkDayReset();
    });
  }

  void stopTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取当前活动应用
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _updateCurrentApp() async {
    if (!Platform.isMacOS) return;

    try {
      // 使用 AppleScript 获取当前活动应用
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get name of first application process whose frontmost is true',
      ]);

      if (result.exitCode == 0) {
        final appName = result.stdout.toString().trim();

        if (appName != _currentApp) {
          // 停止追踪上一个应用
          if (_currentApp != null && _appStartTime.containsKey(_currentApp)) {
            final duration = DateTime.now().difference(_appStartTime[_currentApp]!);
            _appUsageToday[_currentApp!] =
                (_appUsageToday[_currentApp!] ?? Duration.zero) + duration;
            _appStartTime.remove(_currentApp);
          }

          // 开始追踪新应用
          _currentApp = appName;
          _appStartTime[appName] = DateTime.now();
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error getting active app: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎每日重置
  // ─────────────────────────────────────────────────────────────────────────

  void _checkDayReset() {
    final now = DateTime.now();
    if (now.day != _dayStartTime.day) {
      _appUsageToday.clear();
      _appStartTime.clear();
      _dayStartTime = now;
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取统计数据
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取今日摸鱼率
  int getSlackingPercentage() {
    final totalDuration = getTotalUsageTime();
    if (totalDuration.inSeconds == 0) return 0;

    final slackingDuration = getSlackingTime();
    return ((slackingDuration.inSeconds / totalDuration.inSeconds) * 100).round();
  }

  /// 获取总使用时长
  Duration getTotalUsageTime() {
    // 计算当前正在使用的应用时长
    Duration currentDuration = Duration.zero;
    if (_currentApp != null && _appStartTime.containsKey(_currentApp)) {
      currentDuration = DateTime.now().difference(_appStartTime[_currentApp]!);
    }

    // 加上历史时长
    final historyDuration = _appUsageToday.values.fold(
      Duration.zero,
      (total, duration) => total + duration,
    );

    return historyDuration + currentDuration;
  }

  /// 获取工作时长
  Duration getWorkTime() {
    Duration workDuration = Duration.zero;

    // 历史工作时长
    _appUsageToday.forEach((app, duration) {
      if (_workApps.contains(app)) {
        workDuration += duration;
      }
    });

    // 当前工作时长
    if (_currentApp != null &&
        _workApps.contains(_currentApp) &&
        _appStartTime.containsKey(_currentApp)) {
      workDuration += DateTime.now().difference(_appStartTime[_currentApp]!);
    }

    return workDuration;
  }

  /// 获取摸鱼时长
  Duration getSlackingTime() {
    Duration slackingDuration = Duration.zero;

    // 历史摸鱼时长
    _appUsageToday.forEach((app, duration) {
      if (_slackingApps.contains(app)) {
        slackingDuration += duration;
      }
    });

    // 当前摸鱼时长
    if (_currentApp != null &&
        _slackingApps.contains(_currentApp) &&
        _appStartTime.containsKey(_currentApp)) {
      slackingDuration += DateTime.now().difference(_appStartTime[_currentApp]!);
    }

    return slackingDuration;
  }

  /// 获取应用使用列表
  List<AppUsageInfo> getAppUsageList() {
    final Map<String, Duration> allApps = Map.from(_appUsageToday);

    // 添加当前正在使用的应用时长
    if (_currentApp != null && _appStartTime.containsKey(_currentApp)) {
      final currentDuration = DateTime.now().difference(_appStartTime[_currentApp]!);
      allApps[_currentApp!] = (allApps[_currentApp!] ?? Duration.zero) + currentDuration;
    }

    // 转换为列表并排序
    final appList = allApps.entries
        .map((entry) => AppUsageInfo(
              name: entry.key,
              duration: entry.value,
              isWork: _workApps.contains(entry.key),
              isSlacking: _slackingApps.contains(entry.key),
            ))
        .toList();

    appList.sort((a, b) => b.duration.compareTo(a.duration));
    return appList;
  }

  /// 获取主力工作应用
  List<AppUsageInfo> getMainWorkApps() {
    return getAppUsageList()
        .where((app) => app.isWork)
        .take(5)
        .toList();
  }

  /// 获取其他应用
  List<AppUsageInfo> getOtherApps() {
    return getAppUsageList()
        .where((app) => !app.isWork)
        .take(5)
        .toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎配置管理
  // ─────────────────────────────────────────────────────────────────────────

  void addWorkApp(String appName) {
    _workApps.add(appName);
    _slackingApps.remove(appName);
    notifyListeners();
  }

  void addSlackingApp(String appName) {
    _slackingApps.add(appName);
    _workApps.remove(appName);
    notifyListeners();
  }

  void removeFromTracking(String appName) {
    _workApps.remove(appName);
    _slackingApps.remove(appName);
    notifyListeners();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎应用使用信息模型
// ═══════════════════════════════════════════════════════════════════════════

class AppUsageInfo {
  final String name;
  final Duration duration;
  final bool isWork;
  final bool isSlacking;

  AppUsageInfo({
    required this.name,
    required this.duration,
    required this.isWork,
    required this.isSlacking,
  });
}