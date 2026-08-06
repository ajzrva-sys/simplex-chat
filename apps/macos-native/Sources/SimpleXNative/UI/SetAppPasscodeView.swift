import SwiftUI

struct SetAppPasscodeView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var selfDestructPasscode = ""
    @State private var confirmSelfDestruct = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var successMessage = ""

    private let pinLength = 6

    var body: some View {
        Form {
            if model.appPasscodeEnabled {
                Section("Change App Passcode") {
                    SecureField("Current passcode", text: $currentPasscode)
                        .textContentType(.oneTimeCode)
                    SecureField("New passcode (\(pinLength) digits)", text: $newPasscode)
                        .textContentType(.oneTimeCode)
                    SecureField("Confirm new passcode", text: $confirmPasscode)
                        .textContentType(.oneTimeCode)
                    Button("Change Passcode") {
                        Task { await changePasscode() }
                    }
                    .disabled(!canChangePasscode)
                }

                Section("Remove App Passcode") {
                    Button("Remove Passcode", role: .destructive) {
                        Task { await removePasscode() }
                    }
                }
            } else {
                Section("Set App Passcode") {
                    SecureField("New passcode (\(pinLength) digits)", text: $newPasscode)
                        .textContentType(.oneTimeCode)
                    SecureField("Confirm passcode", text: $confirmPasscode)
                        .textContentType(.oneTimeCode)
                    Button("Set Passcode") {
                        Task { await setPasscode() }
                    }
                    .disabled(!canSetPasscode)
                }
            }

            Section("Self-Destruct Passcode") {
                Text("Entering this passcode on the lock screen will erase all app data including chat history, profiles, and settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.selfDestructPasscodeEnabled {
                    Text("Self-destruct passcode is set.")
                        .foregroundStyle(.orange)

                    SecureField("New self-destruct passcode (\(pinLength) digits)", text: $selfDestructPasscode)
                        .textContentType(.oneTimeCode)
                    SecureField("Confirm", text: $confirmSelfDestruct)
                        .textContentType(.oneTimeCode)
                    Button("Update Self-Destruct Passcode") {
                        Task { await setSelfDestruct() }
                    }
                    .disabled(!canSetSelfDestruct)

                    Button("Remove Self-Destruct Passcode", role: .destructive) {
                        Task { await removeSelfDestruct() }
                    }
                } else {
                    SecureField("Self-destruct passcode (\(pinLength) digits)", text: $selfDestructPasscode)
                        .textContentType(.oneTimeCode)
                    SecureField("Confirm", text: $confirmSelfDestruct)
                        .textContentType(.oneTimeCode)
                    Button("Set Self-Destruct Passcode") {
                        Task { await setSelfDestruct() }
                    }
                    .disabled(!canSetSelfDestruct)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {
                showSuccess = false
                dismiss()
            }
        } message: {
            Text(successMessage)
        }
    }

    // MARK: - Validation

    private var canSetPasscode: Bool {
        newPasscode.count == pinLength
            && newPasscode == confirmPasscode
            && newPasscode.allSatisfy(\.isNumber)
    }

    private var canChangePasscode: Bool {
        currentPasscode.count == pinLength
            && newPasscode.count == pinLength
            && newPasscode == confirmPasscode
            && newPasscode.allSatisfy(\.isNumber)
    }

    private var canSetSelfDestruct: Bool {
        selfDestructPasscode.count == pinLength
            && selfDestructPasscode == confirmSelfDestruct
            && selfDestructPasscode.allSatisfy(\.isNumber)
    }

    // MARK: - Actions

    @MainActor
    private func setPasscode() async {
        guard canSetPasscode else { return }
        let result = await model.setAppPasscode(newPasscode)
        switch result {
        case .success:
            successMessage = "App passcode has been set."
            showSuccess = true
            newPasscode = ""
            confirmPasscode = ""
        case .error(let msg):
            errorMessage = msg
            showError = true
        case .wrongPasscode, .selfDestruct:
            break
        }
    }

    @MainActor
    private func changePasscode() async {
        guard canChangePasscode else { return }
        let result = await model.changeAppPasscode(
            current: currentPasscode,
            new: newPasscode
        )
        switch result {
        case .success:
            successMessage = "App passcode has been changed."
            showSuccess = true
            currentPasscode = ""
            newPasscode = ""
            confirmPasscode = ""
        case .error(let msg):
            errorMessage = msg
            showError = true
        case .wrongPasscode, .selfDestruct:
            break
        }
    }

    @MainActor
    private func removePasscode() async {
        let result = await model.removeAppPasscode()
        switch result {
        case .success:
            successMessage = "App passcode has been removed."
            showSuccess = true
        case .error(let msg):
            errorMessage = msg
            showError = true
        case .wrongPasscode, .selfDestruct:
            break
        }
    }

    @MainActor
    private func setSelfDestruct() async {
        guard canSetSelfDestruct else { return }
        let result = await model.setSelfDestructPasscode(selfDestructPasscode)
        switch result {
        case .success:
            successMessage = "Self-destruct passcode has been set."
            showSuccess = true
            selfDestructPasscode = ""
            confirmSelfDestruct = ""
        case .error(let msg):
            errorMessage = msg
            showError = true
        case .wrongPasscode, .selfDestruct:
            break
        }
    }

    @MainActor
    private func removeSelfDestruct() async {
        let result = await model.removeSelfDestructPasscode()
        switch result {
        case .success:
            successMessage = "Self-destruct passcode has been removed."
            showSuccess = true
        case .error(let msg):
            errorMessage = msg
            showError = true
        case .wrongPasscode, .selfDestruct:
            break
        }
    }
}
