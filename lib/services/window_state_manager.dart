/*
 * Purpose: 窗口状态管理服务，管理主窗口状态
 * Inputs: 窗口显示/隐藏事件、用户交互
 * Outputs: 主窗口状态控制
 */

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎窗口状态管理器（简化版）
// ═══════════════════════════════════════════════════════════════════════════

class WindowStateManager {
  static final WindowStateManager _instance = WindowStateManager._internal();
  factory WindowStateManager() => _instance;
  WindowStateManager._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎状态变量
  // ─────────────────────────────────────────────────────────────────────────

  GlobalKey<NavigatorState>? navigatorKey;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置导航键
  // ─────────────────────────────────────────────────────────────────────────

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎显示主窗口
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showMainWindow() async {
    // 恢复窗口可移动和可调整大小
    await windowManager.setMovable(true);
    await windowManager.setResizable(true);

    // 设置主窗口尺寸和样式
    await windowManager.setSize(const Size(1200, 800));
    await windowManager.center();
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setBackgroundColor(Colors.white);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSkipTaskbar(false);

    // 显示并聚焦
    await windowManager.show();
    await windowManager.focus();

    // 导航到主界面
    navigatorKey?.currentState?.pushNamedAndRemoveUntil(
      '/',
      (route) => false,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎初始化主窗口
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initMainWindow() async {
    await showMainWindow();
  }
}