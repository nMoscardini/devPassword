import SwiftUI
import AppKit
import VaultCore

/// A printed page that explains how to get back into the vault. Contains no passwords and no
/// recovery code: the code is written into the boxes by hand, so it is never printed or stored
/// by the computer. Store the sheet like a passport.
struct EmergencySheetView: View {
    let ownerName: String
    let vaultPath: String
    let backupFolder: String?
    let printed: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "lock.shield").font(.system(size: 28))
                VStack(alignment: .leading) {
                    Text("devPassword Emergency Sheet").font(.system(size: 22, weight: .bold))
                    Text("For \(ownerName). Printed \(printed.formatted(date: .long, time: .omitted)).")
                        .font(.system(size: 11)).foregroundStyle(.gray)
                }
            }
            Text("This sheet explains how to open the password vault if the vault password is forgotten, the Mac is lost, or someone else needs to get in. It contains no passwords. Once the recovery code is written below, anyone holding this sheet can open the vault: keep it with your passport and important papers, not near the computer.")
                .font(.system(size: 11))

            section("1. Recovery code") {
                Text("Write the recovery code here by hand, exactly as the app showed it. It has 55 characters in groups of five.")
                    .font(.system(size: 11))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<(row < 2 ? 4 : 3), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 3).stroke(Color.black, lineWidth: 0.8)
                                    .frame(width: 104, height: 30)
                            }
                        }
                    }
                }
                Text("Date written: ____________________   If the code is replaced in the app, write the new one on a new sheet and destroy this one.")
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }

            section("2. Where the vault lives") {
                row("Vault on this Mac", vaultPath)
                row("Encrypted backups", backupFolder ?? "Not set: choose a folder in devPassword Settings > Backup")
                Text("Backups are encrypted. They open with the vault password, or with the recovery code above.")
                    .font(.system(size: 10)).foregroundStyle(.gray)
            }

            section("3. Forgotten vault password, same Mac") {
                step(1, "Open devPassword. On the lock screen choose \"Forgot vault password? Use recovery code\".")
                step(2, "Type the recovery code from this sheet. Spaces, hyphens and capitals do not matter.")
                step(3, "Choose a new vault password when asked.")
            }

            section("4. New or replacement Mac") {
                step(1, "Install devPassword.")
                step(2, "On the first screen choose \"Restore from a backup instead\".")
                step(3, "Choose the newest .dpbackup file from the backup folder above (download it from OneDrive if needed).")
                step(4, "Choose \"Recovery code\", type the code from this sheet, then Check Backup and Restore.")
                step(5, "Unlock with the recovery code and set a new vault password.")
            }

            Spacer(minLength: 0)
            Text("Without the vault password and without this code, the vault cannot be opened by anyone, including the person who built the app. That is by design.")
                .font(.system(size: 10)).foregroundStyle(.gray)
        }
        .foregroundStyle(.black)
        .padding(40)
        .frame(width: 595, height: 842, alignment: .topLeading)
        .background(Color.white)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold))
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium)).frame(width: 120, alignment: .leading)
            Text(value).font(.system(size: 10, design: .monospaced))
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n).").font(.system(size: 11, weight: .medium))
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

enum EmergencySheet {
    /// Opens the standard print panel (print, or save as PDF).
    @MainActor
    static func print(model: AppModel) {
        let sheet = EmergencySheetView(
            ownerName: NSFullUserName(),
            vaultPath: model.vaultURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
            backupFolder: model.backupFolder?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
            printed: Date())
        let view = NSHostingView(rootView: sheet)
        view.frame = NSRect(x: 0, y: 0, width: 595, height: 842)
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = "devPassword Emergency Sheet"
        op.showsPrintPanel = true
        op.run()
        model.vault?.audit("emergency_sheet.printed")
    }
}
