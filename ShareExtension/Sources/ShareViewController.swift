import UIKit
import UniformTypeIdentifiers
import VitalsKit

/// Receives files shared from Settings > Analytics Data (or Files) and drops them in the app group inbox.
/// It does not parse anything: the app reads the inbox the next time it opens, so a several-hundred-MB
/// sysdiagnose never has to fit in an extension's small memory budget. Copies are streamed by FileManager.
final class ShareViewController: UIViewController {
    private let label = UILabel()
    private let detail = UILabel()
    private let done = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        label.text = "Saving to Vitals…"
        label.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        done.addAction(UIAction { [weak self] _ in self?.extensionContext?.completeRequest(returningItems: nil) }, for: .touchUpInside)
        done.isHidden = true
        let stack = UIStackView(arrangedSubviews: [label, detail, done])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { await save() }
    }

    private func save() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var saved: [String] = []
        for p in providers {
            if let name = await copy(p) { saved.append(name) }
        }
        await MainActor.run {
            if saved.isEmpty {
                label.text = "Nothing to save"
                detail.text = "Vitals reads files such as Analytics-….ips.ca.synced, crash and JetsamEvent reports, and sysdiagnose archives."
            } else {
                label.text = saved.count == 1 ? "Saved to Vitals" : "Saved \(saved.count) files to Vitals"
                detail.text = "Open Vitals and it will read \(saved.count == 1 ? "it" : "them") on this phone. Nothing is uploaded."
                UIAccessibility.post(notification: .announcement, argument: label.text)
            }
            done.isHidden = false
        }
    }

    /// Copies one attachment into the inbox. Returns the file name, or nil.
    private func copy(_ provider: NSItemProvider) async -> String? {
        let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .data) == true } ?? UTType.data.identifier
        let suggested = provider.suggestedName
        return await withCheckedContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else { cont.resume(returning: nil); return }
                let name = suggested.map { n in url.pathExtension.isEmpty || n.hasSuffix(url.pathExtension) ? n : "\(n).\(url.pathExtension)" } ?? url.lastPathComponent
                let dest = SharedContainer.inboxURL.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dest)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: name)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
