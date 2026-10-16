import AppKit

final class StatusItemController: NSObject {
    private let item: NSStatusItem
    // 全等宽而非 monospacedDigit：后者只保证数字等宽，帧内的 "."、单位字母、"--" 不等宽，实测仍抖 41.68pt
    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func update(attributed: NSAttributedString) {
        item.button?.attributedTitle = attributed
    }

    func setToolTip(_ text: String) {
        item.button?.toolTip = text
    }

    func setMenu(_ menu: NSMenu) {
        item.menu = menu
    }

    /// 状态项在屏幕上的左边缘；用于检测是否被刘海挤压
    var itemMinX: CGFloat? {
        let f = item.button?.window?.frame ?? .zero
        return f.width > 0 ? f.minX : nil
    }

    var itemMaxX: CGFloat? {
        let f = item.button?.window?.frame ?? .zero
        return f.width > 0 ? f.maxX : nil
    }

    func width(of text: String) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    /// 刘海右侧可用菜单栏区域的左边缘；无刘海屏幕为 nil
    var safeAreaMinX: CGFloat? {
        NSScreen.screens.first?.auxiliaryTopRightArea?.minX
    }
}
