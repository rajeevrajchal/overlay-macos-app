import Cocoa

final class SizeSettingsViewController: NSViewController {

    var onApply: ((CGFloat, CGFloat) -> Void)?
    var onReset: (() -> Void)?

    var currentSize: NSSize = NSSize(width: 600, height: 400) {
        didSet {
            guard isViewLoaded else { return }
            widthField.integerValue  = Int(currentSize.width)
            heightField.integerValue = Int(currentSize.height)
        }
    }

    private let widthField  = SizeSettingsViewController.makeField()
    private let heightField = SizeSettingsViewController.makeField()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 110))

        let wLabel = label("Width")
        let hLabel = label("Height")

        let resetBtn = NSButton(title: "Reset", target: self, action: #selector(resetTapped))
        resetBtn.bezelStyle = .rounded
        resetBtn.translatesAutoresizingMaskIntoConstraints = false

        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        applyBtn.bezelStyle = .rounded
        applyBtn.keyEquivalent = "\r"
        applyBtn.translatesAutoresizingMaskIntoConstraints = false

        for v in [wLabel, widthField, hLabel, heightField, resetBtn, applyBtn] {
            root.addSubview(v)
        }

        NSLayoutConstraint.activate([
            wLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            wLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            wLabel.widthAnchor.constraint(equalToConstant: 48),

            widthField.leadingAnchor.constraint(equalTo: wLabel.trailingAnchor, constant: 8),
            widthField.centerYAnchor.constraint(equalTo: wLabel.centerYAnchor),
            widthField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            hLabel.leadingAnchor.constraint(equalTo: wLabel.leadingAnchor),
            hLabel.topAnchor.constraint(equalTo: wLabel.bottomAnchor, constant: 10),
            hLabel.widthAnchor.constraint(equalToConstant: 48),

            heightField.leadingAnchor.constraint(equalTo: hLabel.trailingAnchor, constant: 8),
            heightField.centerYAnchor.constraint(equalTo: hLabel.centerYAnchor),
            heightField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            resetBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            resetBtn.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            applyBtn.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            applyBtn.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        widthField.integerValue  = Int(currentSize.width)
        heightField.integerValue = Int(currentSize.height)
    }

    @objc private func applyTapped() {
        let w = CGFloat(widthField.integerValue)
        let h = CGFloat(heightField.integerValue)
        guard w >= 200, h >= 200 else { return }
        onApply?(w, h)
    }

    @objc private func resetTapped() {
        onReset?()
    }

    // MARK: - Helpers

    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 12)
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }

    private static func makeField() -> NSTextField {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 200
        formatter.usesGroupingSeparator = false

        let f = NSTextField()
        f.formatter = formatter
        f.placeholderString = "px"
        f.alignment = .right
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }
}
