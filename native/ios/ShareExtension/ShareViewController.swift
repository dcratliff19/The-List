import UIKit
import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
  private var sharedURL: String?

  override func viewDidLoad() {
    super.viewDidLoad()
    placeholder = "Add a note (optional). Open The List to choose a project and save."
    for item in extensionContext?.inputItems as? [NSExtensionItem] ?? [] {
      for provider in item.attachments ?? [] {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
            DispatchQueue.main.async {
              self.sharedURL = (value as? URL)?.absoluteString
              self.validateContent()
            }
          }
          return
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, _ in
            DispatchQueue.main.async {
              self.sharedURL = value as? String
              self.validateContent()
            }
          }
          return
        }
      }
    }
  }

  override func isContentValid() -> Bool {
    !(sharedURL ?? "").isEmpty
  }

  override func didSelectPost() {
    let group = Bundle.main.object(forInfoDictionaryKey: "TheListAppGroup") as? String
      ?? "group.app.thelist.shared"
    guard let defaults = UserDefaults(suiteName: group), let value = sharedURL else { return }
    // Queue input for explicit review in the main app; the extension owns no project data.
    var pending = defaults.stringArray(forKey: "pendingShares") ?? []
    guard pending.count < 100 else {
      let alert = UIAlertController(
        title: "Review pending links",
        message: "Open The List to review your pending links before sharing more.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
      return
    }
    pending.append(String((value + "\n" + (contentText ?? "")).prefix(32000)))
    defaults.set(pending, forKey: "pendingShares")
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  override func configurationItems() -> [Any]! {
    []
  }
}
