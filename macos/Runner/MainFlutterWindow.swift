/*
 * Purpose: 主窗口管理，集成原生托盘 popover 控制器
 * Inputs: Flutter 视图控制器、托盘事件
 * Outputs: 主窗口显示、托盘 popover 管理、Flutter 通信
 */

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    // ─────────────────────────────────────────────────────────────────────────
    // ▎属性定义
    // ─────────────────────────────────────────────────────────────────────────

    private var trayPopoverController: TrayPopoverController?
    private var trayChannel: FlutterMethodChannel?

    // ─────────────────────────────────────────────────────────────────────────
    // ▎窗口初始化
    // ─────────────────────────────────────────────────────────────────────────

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        // 注册插件
        RegisterGeneratedPlugins(registry: flutterViewController)

        // 设置托盘功能
        setupTrayPopover(flutterViewController: flutterViewController)

        // 设置窗口属性
        setupWindowProperties()

        super.awakeFromNib()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎设置托盘 Popover
    // ─────────────────────────────────────────────────────────────────────────

    private func setupTrayPopover(flutterViewController: FlutterViewController) {
        // 创建 MethodChannel
        trayChannel = FlutterMethodChannel(
            name: "com.vibeloft.desktop/tray",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )

        // 创建托盘控制器
        trayPopoverController = TrayPopoverController()

        // 初始化托盘控制器（不再共享视图控制器）
        trayPopoverController?.setupFlutterViewController(
            flutterViewController,
            channel: trayChannel!
        )

        // 设置 Flutter 端调用处理
        setupMethodCallHandler()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎设置 Flutter 方法调用处理
    // ─────────────────────────────────────────────────────────────────────────

    private func setupMethodCallHandler() {
        trayChannel?.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "showPopover":
                self?.trayPopoverController?.showPopover()
                result(nil)

            case "closePopover":
                self?.trayPopoverController?.closePopover()
                result(nil)

            case "getTrayPosition":
                let position = self?.trayPopoverController?.getTrayIconPosition()
                result(position)

            case "updateTrayIcon":
                if let args = call.arguments as? [String: Any],
                   let imageName = args["imageName"] as? String {
                    self?.trayPopoverController?.updateTrayIcon(imageName: imageName)
                }
                result(nil)

            case "setToolTip":
                if let args = call.arguments as? [String: Any],
                   let tooltip = args["tooltip"] as? String {
                    self?.trayPopoverController?.setToolTip(tooltip)
                }
                result(nil)

            case "showMainWindow":
                self?.showMainWindow()
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎设置窗口属性
    // ─────────────────────────────────────────────────────────────────────────

    private func setupWindowProperties() {
        // 设置窗口样式
        self.titlebarAppearsTransparent = false
        self.isMovableByWindowBackground = true
        self.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]

        // 设置最小尺寸
        self.minSize = NSSize(width: 800, height: 600)

        // 居中显示
        self.center()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎显示主窗口
    // ─────────────────────────────────────────────────────────────────────────

    private func showMainWindow() {
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎托盘 Popover 控制器
// ═══════════════════════════════════════════════════════════════════════════

class TrayPopoverController: NSObject {
    // ─────────────────────────────────────────────────────────────────────────
    // ▎属性定义
    // ─────────────────────────────────────────────────────────────────────────

    private var popover: NSPopover?
    private var statusItem: NSStatusItem?
    private var flutterEngine: FlutterEngine? // 独立的 Flutter 引擎
    private var flutterViewController: FlutterViewController?
    private var popoverViewController: NSViewController?
    private weak var channel: FlutterMethodChannel?

    // Popover 内容大小
    private let popoverSize = NSSize(width: 340, height: 500)

    // ─────────────────────────────────────────────────────────────────────────
    // ▎初始化
    // ─────────────────────────────────────────────────────────────────────────

    override init() {
        super.init()
        setupStatusItem()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎设置状态栏图标
    // ─────────────────────────────────────────────────────────────────────────

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            // 设置图标
            if let image = NSImage(named: "AppIcon") {
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }

            // 设置点击事件
            button.action = #selector(togglePopover)
            button.target = self

            // 设置右键菜单
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎配置 Flutter 视图控制器
    // ─────────────────────────────────────────────────────────────────────────

    func setupFlutterViewController(_ mainController: FlutterViewController, channel: FlutterMethodChannel) {
        self.channel = channel

        // 创建独立的 Flutter 引擎给 Popover 使用
        flutterEngine = FlutterEngine(name: "popover_engine", project: nil)

        // 设置初始路由为托盘界面
        flutterEngine?.run(withEntrypoint: "popoverMain")

        // 创建 Popover 专用的 Flutter 视图控制器
        flutterViewController = FlutterViewController(engine: flutterEngine!, nibName: nil, bundle: nil)

        // 创建 popover 容器视图控制器
        popoverViewController = NSViewController()
        popoverViewController?.view = NSView(frame: NSRect(origin: .zero, size: popoverSize))

        // 将 Popover 的 Flutter 视图添加到容器中
        if let flutterView = flutterViewController?.view {
            popoverViewController?.view.addSubview(flutterView)
            flutterView.frame = popoverViewController!.view.bounds
            flutterView.autoresizingMask = [.width, .height]
        }

        // 为 Popover 引擎创建独立的 MethodChannel
        if let binaryMessenger = flutterEngine?.binaryMessenger {
            let popoverChannel = FlutterMethodChannel(
                name: "com.vibeloft.desktop/popover",
                binaryMessenger: binaryMessenger
            )

            // 设置 Popover 专用的方法处理
            setupPopoverMethodHandler(popoverChannel)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎Popover 专用方法处理
    // ─────────────────────────────────────────────────────────────────────────

    private func setupPopoverMethodHandler(_ popoverChannel: FlutterMethodChannel) {
        popoverChannel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "closePopover":
                self?.closePopover()
                result(nil)
            case "showMainWindow":
                self?.showMainWindow()
                result(nil)
            case "exitApp":
                self?.quitApp()
                result(nil)
            case "openURL":
                if let args = call.arguments as? [String: Any],
                   let urlString = args["url"] as? String,
                   let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎切换 Popover 显示状态
    // ─────────────────────────────────────────────────────────────────────────

    @objc private func togglePopover() {
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseUp {
                // 右键显示菜单
                showContextMenu()
            } else {
                // 左键切换 popover
                if popover?.isShown == true {
                    closePopover()
                } else {
                    showPopover()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎显示 Popover
    // ─────────────────────────────────────────────────────────────────────────

    func showPopover() {
        guard let button = statusItem?.button,
              let popoverViewController = popoverViewController else {
            return
        }

        // 如果已存在，先关闭
        if popover != nil {
            closePopover()
        }

        // 创建新的 popover
        popover = NSPopover()
        popover?.contentSize = popoverSize
        popover?.behavior = .transient // 点击外部自动关闭
        popover?.animates = true
        popover?.contentViewController = popoverViewController

        // 设置外观为浅色模式
        if #available(macOS 10.14, *) {
            popover?.appearance = NSAppearance(named: .aqua)
        }

        // 显示 popover
        popover?.show(relativeTo: button.bounds,
                     of: button,
                     preferredEdge: .minY)

        // 设置透明背景，消除黑色圆角
        // 需要在 popover 显示后设置
        DispatchQueue.main.async { [weak self] in
            if let contentView = self?.popover?.contentViewController?.view {
                // 设置视图背景透明
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
                contentView.layer?.isOpaque = false
            }
        }

        // 通知 Flutter 端 popover 已显示
        channel?.invokeMethod("onPopoverShown", arguments: nil)

        // 监听关闭事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverDidClose),
            name: NSPopover.didCloseNotification,
            object: popover
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎关闭 Popover
    // ─────────────────────────────────────────────────────────────────────────

    func closePopover() {
        popover?.performClose(nil)
        popover = nil

        // 通知 Flutter 端 popover 已关闭
        channel?.invokeMethod("onPopoverClosed", arguments: nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎Popover 关闭事件处理
    // ─────────────────────────────────────────────────────────────────────────

    @objc private func popoverDidClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(
            self,
            name: NSPopover.didCloseNotification,
            object: popover
        )
        popover = nil

        // 通知 Flutter 端
        channel?.invokeMethod("onPopoverClosed", arguments: nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎显示右键菜单
    // ─────────────────────────────────────────────────────────────────────────

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(
            title: "显示主窗口",
            action: #selector(showMainWindow),
            keyEquivalent: ""
        ))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(
            title: "退出",
            action: #selector(quitApp),
            keyEquivalent: "q"
        ))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // 清除菜单，恢复点击行为
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎显示主窗口
    // ─────────────────────────────────────────────────────────────────────────

    @objc private func showMainWindow() {
        // 关闭 popover
        closePopover()

        // 通知 Flutter 端显示主窗口
        channel?.invokeMethod("showMainWindow", arguments: nil)

        // 激活应用
        NSApp.activate(ignoringOtherApps: true)
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎退出应用
    // ─────────────────────────────────────────────────────────────────────────

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎获取托盘图标位置（供 Flutter 调用）
    // ─────────────────────────────────────────────────────────────────────────

    func getTrayIconPosition() -> [String: Any]? {
        guard let button = statusItem?.button,
              let window = button.window else {
            return nil
        }

        let buttonFrame = button.frame

        // 转换为屏幕坐标
        let screenFrame = window.convertToScreen(buttonFrame)

        return [
            "x": screenFrame.origin.x,
            "y": screenFrame.origin.y,
            "width": screenFrame.width,
            "height": screenFrame.height
        ]
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎更新托盘图标
    // ─────────────────────────────────────────────────────────────────────────

    func updateTrayIcon(imageName: String) {
        if let button = statusItem?.button,
           let image = NSImage(named: imageName) {
            image.size = NSSize(width: 18, height: 18)
            button.image = image
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ▎设置工具提示
    // ─────────────────────────────────────────────────────────────────────────

    func setToolTip(_ tooltip: String) {
        statusItem?.button?.toolTip = tooltip
    }
}
