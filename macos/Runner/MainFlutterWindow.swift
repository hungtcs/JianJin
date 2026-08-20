import Cocoa
import FlutterMacOS

/// 最小窗口尺寸。三端必须一致，见 test/window_min_size_contract_test.dart。
///
/// 取 800x600：这本就是 MainMenu.xib 里的初始内容尺寸，设成下限不会在启动时
/// 把窗口撑大，同时挡住「拖到只剩一条标题栏」这种完全没法用的尺寸。
/// 布局的固定开销是 34(标题) + 44(传输栏) + 34(全片条) + 96(时间轴) = 208，
/// 600 高仍给视频区留下近 400。
let kMinWindowWidth = 800
let kMinWindowHeight = 600

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 用 contentMinSize 而不是 minSize：前者限的是内容区，正好对应 Flutter
    // 的绘制区域；后者含标题栏，会让实际可用高度比设定值少一截。
    self.contentMinSize = NSSize(width: kMinWindowWidth, height: kMinWindowHeight)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
