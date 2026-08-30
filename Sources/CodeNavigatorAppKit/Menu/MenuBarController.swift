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

    /// Shown in place of the list when nothing has been opened yet.
    private static let emptyRecentProjectsTitle = "최근 항목 없음"

    private let perform: (MenuCommand) -> Void
    private let availability: () -> MenuAvailability
    private let recentProjects: () -> [RecentProject]
    private let openRecentProject: (String) -> Void
    private var commandsByItem: [ObjectIdentifier: MenuCommand] = [:]
    private var recentPathsByItem: [ObjectIdentifier: String] = [:]

    public init(
        availability: @escaping () -> MenuAvailability,
        perform: @escaping (MenuCommand) -> Void,
        recentProjects: @escaping () -> [RecentProject] = { [] },
        openRecentProject: @escaping (String) -> Void = { _ in }
    ) {
        self.availability = availability
        self.perform = perform
        self.recentProjects = recentProjects
        self.openRecentProject = openRecentProject
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
        // Auto-enabling must stay ON. It is what makes AppKit call `validateMenuItem` on
        // each item's target — which is where this controller decides, from
        // `MenuAvailability`, whether an edit command is live (REQ-010 AC-5) and which
        // input mode carries the tick (REQ-010 AC-3).
        //
        // Turning it off does the opposite of what the name suggests: AppKit then stops
        // asking anyone and just reads `isEnabled`, which nothing sets. Every item stayed
        // enabled and no tick ever appeared, while the unit tests passed because they
        // called `validateMenuItem` directly and never went through AppKit.
        menu.autoenablesItems = true
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
        if descriptor.command == .openRecentProject {
            // Filled in when the menu opens, not now. The list changes every time a project
            // is opened, and a submenu built once at launch would show the state the
            // application had before the user did anything (REQ-001 AC-2).
            let submenu = NSMenu(title: descriptor.title)
            submenu.autoenablesItems = true
            submenu.delegate = self
            item.submenu = submenu
        } else if !descriptor.submenu.isEmpty {
            let submenu = NSMenu(title: descriptor.title)
            submenu.autoenablesItems = true
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

    @objc private func fireRecentProject(_ sender: NSMenuItem) {
        // Keyed by the row, not by the title: two checkouts of one repository share a name
        // and differ only in path.
        guard let path = recentPathsByItem[ObjectIdentifier(sender)] else { return }
        openRecentProject(path)
    }
}

extension MenuBarController: NSMenuDelegate {

    /// Rebuilds the recent-projects submenu each time it opens.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            recentPathsByItem.removeValue(forKey: ObjectIdentifier(item))
        }
        menu.removeAllItems()

        let projects = recentProjects()
        guard !projects.isEmpty else {
            let placeholder = NSMenuItem(title: Self.emptyRecentProjectsTitle, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
            return
        }

        for project in projects {
            let item = NSMenuItem(title: project.name, action: #selector(fireRecentProject(_:)), keyEquivalent: "")
            item.target = self
            item.toolTip = project.rootPath
            recentPathsByItem[ObjectIdentifier(item)] = project.rootPath
            menu.addItem(item)
        }
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
