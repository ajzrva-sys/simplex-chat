import SwiftUI

struct AppLockView: View {
    @ObservedObject var model: AppModel
    @State private var enteredDigits: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var showError = false
    @State private var errorMessage = ""

    private let pinLength = 6

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("App Locked")
                .font(.title2.weight(.semibold))

            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<pinLength, id: \.self) { index in
                    Circle()
                        .fill(index < enteredDigits.count ? Color.primary : Color.clear)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().stroke(Color.primary, lineWidth: 1.5)
                        )
                }
            }
            .offset(x: shakeOffset)
            .animation(.default, value: shakeOffset)

            if showError {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .transition(.opacity)
            }

            // Numeric keypad
            VStack(spacing: 12) {
                ForEach(0..<3) { row in
                    HStack(spacing: 24) {
                        ForEach(1...3, id: \.self) { col in
                            let digit = row * 3 + col
                            pinButton("\(digit)")
                        }
                    }
                }
                HStack(spacing: 24) {
                    // Empty spacer for alignment
                    Color.clear.frame(width: 72, height: 72)
                    pinButton("0")
                    // Delete button
                    Button {
                        guard !enteredDigits.isEmpty else { return }
                        enteredDigits.removeLast()
                        showError = false
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .frame(width: 72, height: 72)
                    }
                    .buttonStyle(.plain)
                    .disabled(enteredDigits.isEmpty)
                }
            }

            Spacer()
        }
        .padding(32)
        .frame(width: 380)
        .onAppear {
            enteredDigits = ""
            showError = false
        }
    }

    @ViewBuilder
    private func pinButton(_ digit: String) -> some View {
        Button {
            guard enteredDigits.count < pinLength else { return }
            enteredDigits.append(digit)
            showError = false

            if enteredDigits.count == pinLength {
                Task {
                    await verifyPasscode(enteredDigits)
                }
            }
        } label: {
            Text(digit)
                .font(.title)
                .frame(width: 72, height: 72)
                .background(Circle().fill(.quaternary))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func verifyPasscode(_ passcode: String) async {
        let result = await model.verifyAppPasscode(passcode)
        switch result {
        case .success:
            break
        case .wrongPasscode:
            shakeAndReset(message: "Incorrect passcode. Try again.")
        case .selfDestruct:
            shakeAndReset(message: "All data has been erased.")
        case .error(let message):
            shakeAndReset(message: message)
        }
    }

    private func shakeAndReset(message: String) {
        errorMessage = message
        showError = true
        withAnimation(.easeInOut(duration: 0.06).repeatCount(5, autoreverses: true)) {
            shakeOffset = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            shakeOffset = 0
            enteredDigits = ""
        }
    }
}
