/*
 * Purpose: 系统托盘管理服务，使用原生 NSPopover 实现
 * Inputs: 原生托盘事件、Flutter 方法调用
 * Outputs: 原生托盘图标、NSPopover 显示、主窗口控制
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎托盘服务类 - 使用原生 NSPopover
// ═══════════════════════════════════════════════════════════════════════════

class TrayService {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Method Channel 定义
  // ─────────────────────────────────────────────────────────────────────────

  static const _channel = MethodChannel('com.vibeloft.desktop/tray');

  // 保存回调引用
  VoidCallback? _onPopoverShown;
  VoidCallback? _onPopoverClosed;
  VoidCallback? _onShowMainWindow;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎初始化托盘（原生实现）
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initSystemTray() async {
    // 设置方法调用处理器
    _channel.setMethodCallHandler(_handleMethodCall);

    // 设置工具提示
    await _channel.invokeMethod('setToolTip', {
      'tooltip': 'VibeLoft Desktop',
    });

    // 注意：原生代码已经在 TrayPopoverController 初始化时创建了托盘图标
    // 所以这里不需要再调用 tray_manager
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎处理原生端回调
  // ─────────────────────────────────────────────────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPopoverShown':
        _onPopoverShown?.call();
        break;
      case 'onPopoverClosed':
        _onPopoverClosed?.call();
        break;
      case 'showMainWindow':
        _onShowMainWindow?.call();
        await _showMainWindow();
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎显示原生 Popover
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showPopover() async {
    try {
      await _channel.invokeMethod('showPopover');
    } on PlatformException catch (e) {
      debugPrint('Failed to show popover: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎关闭原生 Popover
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> closePopover() async {
    try {
      await _channel.invokeMethod('closePopover');
    } on PlatformException catch (e) {
      debugPrint('Failed to close popover: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取托盘图标位置
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getTrayPosition() async {
    try {
      final result = await _channel.invokeMethod('getTrayPosition');
      return result != null ? Map<String, dynamic>.from(result) : null;
    } on PlatformException catch (e) {
      debugPrint('Failed to get tray position: ${e.message}');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎更新托盘图标
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> updateTrayIcon(String imageName) async {
    try {
      await _channel.invokeMethod('updateTrayIcon', {
        'imageName': imageName,
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to update tray icon: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎显示主窗口
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置 Popover 显示回调
  // ─────────────────────────────────────────────────────────────────────────

  void setOnPopoverShown(VoidCallback callback) {
    _onPopoverShown = callback;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置 Popover 关闭回调
  // ─────────────────────────────────────────────────────────────────────────

  void setOnPopoverClosed(VoidCallback callback) {
    _onPopoverClosed = callback;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置显示主窗口回调
  // ─────────────────────────────────────────────────────────────────────────

  void setOnShowMainWindow(VoidCallback callback) {
    _onShowMainWindow = callback;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎销毁托盘
  // ─────────────────────────────────────────────────────────────────────────

  void destroy() {
    _onPopoverShown = null;
    _onPopoverClosed = null;
    _onShowMainWindow = null;
  }
}