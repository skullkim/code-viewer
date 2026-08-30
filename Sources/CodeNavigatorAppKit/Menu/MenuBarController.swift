import AppKit

/// Turns the menu descriptors into a live menu bar and routes what it fires.
///
/// This is where the key-routing contract actually takes effect. ADR-0102 decided the
/// application claims Command combinations and nothing else, and the mechanism for
/// claiming them *is* the menu bar: AppKit offers each Command chord to the menu first, and
/// anything the menu does not take falls through to the editor view's `keyDown`. Without a
/// menu installed, ⌘O and ⌘P would reach Neovim as `<D-o>` and `<D-p>` — the REQ-011 AC-2
/// conflict the design exists to prevent.
@MainActor
public final class MenuBarController: NSObject {

    private let perform: (MenuCommand) -> Void
    private let availability: () -> MenuAvailability
    private var commandsByItem: [ObjectIdentifier: MenuCommand] = [:]

    public init(
        availability: @escaping () -> MenuAvailability,
        perform: @escaping (MenuCommand) -> Void
    ) {
        self.availability = availability
        self.perform = perform
    }

    /// Builds the menu bar and installs it.
    public func install(into application: NSApplication = .shared) {
        let mainMenu = NSMenu()
        for descriptor in AppMenuBuilder.menus() {
            let item = NSMenuItem()
            item.submenu = menu(from: descriptor)
            mainMenu.addItem(item)
        }
        application.mainMenu = mainMenu
    }

    /// Builds one top-level menu, for tests that inspect the result.
    public func menu(from descriptor: MenuDescriptor) -> NSMenu {
        let menu = NSMenu(title: descriptor.title)
        // Validation is ours, not AppKit's responder-chain guesswork: whether an edit
        // command is live depends on the input mode (REQ-010 AC-5), which no responder
        // knows about.
        menu.autoenablesItems = false
        for descriptor in descriptor.items {
            menu.addItem(item(from: descriptor))
        }
        return menu
    }

    private func item(from descriptor: MenuItemDescriptor) -> NSMenuItem {
        guard !descriptor.isSeparator else {
            return .separator()
        }

        let item = NSMenuItem(
            title: descriptor.title,
            action: descriptor.command == nil ? nil : #selector(fire(_:)),
            // An uppercase key equivalent already implies Shift. Naming both makes the
            // match fail silently — measured in the spike, where ⇧⌘F leaked through to
            // Neovim because of exactly this. The descriptors keep it lowercase and the
            // modifier mask carries the Shift.
            keyEquivalent: descriptor.keyEquivalent.lowercased()
        )
        item.keyEquivalentModifierMask = modifierMask(descriptor.modifiers)
        item.target = descriptor.command == nil ? nil : self

        if let command = descriptor.command {
            commandsByItem[ObjectIdentifier(item)] = command
        }
        if !descriptor.submenu.isEmpty {
            let submenu = NSMenu(title: descriptor.title)
            submenu.autoenablesItems = false
            for child in descriptor.submenu {
                submenu.addItem(self.item(from: child))
            }
            item.submenu = submenu
        }
        return item
    }

    private func modifierMask(_ modifiers: KeyModifiers) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { mask.insert(.command) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.control) { mask.insert(.control) }
        return mask
    }

    /// The command a built item runs, for tests that walk the menu.
    public func command(for item: NSMenuItem) -> MenuCommand? {
        commandsByItem[ObjectIdentifier(item)]
    }

    @objc private func fire(_ sender: NSMenuItem) {
        guard let command = commandsByItem[ObjectIdentifier(sender)] else { return }
        perform(command)
    }
}

extension MenuBarController: NSMenuItemValidation {
    /// Decides whether a row is live, from `MenuAvailability`.
    ///
    /// The rule that matters is REQ-010 AC-5: the standard editing commands are live only
    /// in standard mode, because in Vim mode `u`, `y` and `p` already do that work and two
    /// routes into one buffer split the undo history.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = commandsByItem[ObjectIdentifier(menuItem)] else {
            return true
        }
        let availability = availability()
        menuItem.state = availability.isChecked(command) ? .on : .off
        return availability.isEnabled(command)
    }
}
