/*
 * Purpose: 应用主入口，提供路由和状态管理配置
 * Inputs: 用户导航事件，系统启动
 * Outputs: Flutter 应用实例，包含 Claude 监控页面
 */

import 'package:english_words/english_words.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'pages/history_page.dart';
import 'pages/usage_monitor_page.dart';
import 'providers/usage_monitor_provider.dart';
import 'services/app_usage_tracker.dart';
import 'services/data_sync_service.dart';
import 'services/tray_service.dart';
import 'services/window_state_manager.dart';
import 'state/usage_state.dart';
import 'widgets/tray_popover.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎应用入口
// ═══════════════════════════════════════════════════════════════════════════

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─────────────────────────────────────────────────────────────────────────
  // 初始化窗口管理器
  // ─────────────────────────────────────────────────────────────────────────
  await windowManager.ensureInitialized();

  // 始终启动主窗口
  const windowOptions = WindowOptions(
    size: Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'VibeLoft Desktop',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 初始化系统托盘
  // ─────────────────────────────────────────────────────────────────────────
  await TrayService().initSystemTray();

  // ─────────────────────────────────────────────────────────────────────────
  // 启动应用使用追踪
  // ─────────────────────────────────────────────────────────────────────────
  AppUsageTracker().startTracking();

  // ─────────────────────────────────────────────────────────────────────────
  // 初始化数据同步服务（主窗口）
  // ─────────────────────────────────────────────────────────────────────────
  DataSyncService().initialize(false);

  runApp(MyApp());
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎Popover 专用入口
// ═══════════════════════════════════════════════════════════════════════════

@pragma('vm:entry-point')
void popoverMain() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动应用使用追踪（共享数据）
  AppUsageTracker().startTracking();

  // 初始化数据同步服务（Popover）
  DataSyncService().initialize(true);

  runApp(PopoverApp());
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎主应用组件
// ═══════════════════════════════════════════════════════════════════════════

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 窗口关闭事件处理
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void onWindowClose() async {
    // 隐藏窗口而不是退出应用
    await windowManager.hide();
  }

  @override
  Widget build(BuildContext context) {
    // 创建全局导航键
    final navigatorKey = GlobalKey<NavigatorState>();

    // 设置导航键到窗口状态管理器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WindowStateManager().setNavigatorKey(navigatorKey);
    });

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MyAppState()),
        ChangeNotifierProvider(create: (_) => UsageState()),
        ChangeNotifierProvider.value(value: AppUsageTracker()),
        ChangeNotifierProvider(
          create: (_) => UsageMonitorProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'VibeLoft Desktop',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: MainNavigator(),
        routes: {
          '/tray_popover': (context) => const TrayPopover(),
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎导航管理
// ═══════════════════════════════════════════════════════════════════════════

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0; // 默认显示 Monitor

  final List<Widget> _pages = [
    const UsageMonitorPage(), // 索引0 - Monitor
    const HistoryPage(), // 索引1 - History
  ];

  // ─────────────────────────────────────────────────────────────────────────
  // 构建导航项
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isExtended,
  }) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isExtended ? 12 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: isExtended
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  size: 24,
                ),
                if (isExtended) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // ─────────────────────────────────────────────────────────────────
          // 响应式断点：屏幕宽度 > 800 时展开导航栏
          // ─────────────────────────────────────────────────────────────────
          final bool isExtended = constraints.maxWidth > 800;

          return Row(
            children: [
              // ─────────────────────────────────────────────────────────────
              // 自定义侧边导航栏
              // ─────────────────────────────────────────────────────────────
              Container(
                width: isExtended ? 140 : 56,
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildNavItem(
                      context,
                      index: 0,
                      icon: Icons.analytics_outlined,
                      selectedIcon: Icons.analytics,
                      label: '监控',
                      isExtended: isExtended,
                    ),
                    _buildNavItem(
                      context,
                      index: 1,
                      icon: Icons.history_outlined,
                      selectedIcon: Icons.history,
                      label: '历史',
                      isExtended: isExtended,
                    ),
                  ],
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              // 页面内容
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: _pages,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎Popover 专用应用
// ═══════════════════════════════════════════════════════════════════════════

class PopoverApp extends StatelessWidget {
  const PopoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppUsageTracker()),
        ChangeNotifierProvider(
          create: (_) => UsageMonitorProvider()..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'VibeLoft Popover',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        debugShowCheckedModeBanner: false,
        home: const TrayPopover(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎应用状态
// ═══════════════════════════════════════════════════════════════════════════

class MyAppState extends ChangeNotifier {
  var current = WordPair.random();
}
