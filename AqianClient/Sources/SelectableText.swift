import SwiftUI
import UIKit

/// 可选中、链接可点的文字视图。
/// SwiftUI 的 Text + textSelection 在 ScrollView 里经常只能整段复制、链接点不动，
/// 这里直接用 UITextView：原生支持部分选中复制和数据检测出的链接。
struct SelectableText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let color: UIColor
    let linkColor: UIColor
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.dataDetectorTypes = [.link]
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        let attr = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: color
        ])
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 6
        attr.addAttribute(.paragraphStyle, value: para,
                          range: NSRange(location: 0, length: attr.length))
        if tv.attributedText.string != text ||
            tv.attributedText.length != text.count {
            tv.attributedText = attr
        }
        context.coordinator.parent = self
        context.coordinator.recalc(tv)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableText
        private var lastWidth: CGFloat = 0

        init(_ p: SelectableText) { parent = p }

        func recalc(_ tv: UITextView) {
            DispatchQueue.main.async {
                let w = tv.bounds.width
                guard w > 0, abs(w - self.lastWidth) > 0.5 else { return }
                self.lastWidth = w
                let size = tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude))
                if abs(size.height - self.parent.height) > 0.5 {
                    self.parent.height = size.height
                }
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {}

        @available(iOS 10.0, *)
        func textView(_ textView: UITextView,
                      shouldInteractWith URL: URL,
                      in characterRange: NSRange,
                      interaction: UITextItemInteraction) -> Bool {
            UIApplication.shared.open(URL)
            return false
        }
    }
}

/// 一条消息的正文：外部只给字符串，内部自己量高度。
struct MsgText: View {
    let text: String
    let color: UIColor
    @State private var height: CGFloat = 20

    var body: some View {
        SelectableText(text: text,
                       fontSize: 17,
                       color: color,
                       linkColor: UIColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1.0),
                       height: $height)
            .frame(height: height)
            .fixedSize(horizontal: false, vertical: true)
    }
}
