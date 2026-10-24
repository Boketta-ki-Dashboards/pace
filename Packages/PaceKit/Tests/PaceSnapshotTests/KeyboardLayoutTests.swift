import DesignSystem
import Foundation
import PaceCore
import PaceTestSupport
@testable import SocialFeature
import SwiftUI
import Testing
import UIKit

/// Chat-Eingabe bei offener Tastatur im echten Fenster (P0 Auftrag 4): Aufbau wie `MainTabView` – Seitenleiste mit
/// Social-Seite, darin ein Chat im `NavigationStack`, Tab-Leiste verschwindet bei offener Tastatur.
///
/// Ob der Simulator eine Bildschirmtastatur zeigt, hängt von seiner Einstellung ab (mit verbundener Hardware-Tastatur
/// erscheint keine). Erscheint sie, muss das Eingabefeld vollständig darüber liegen; sonst protokolliert der Test, dass
/// die Prüfung auf dem Gerät erfolgen muss.
@MainActor
@Suite(.serialized)
struct KeyboardLayoutTests {
    @Test func chatInputStaysAboveTheKeyboard() async throws {
        let (list, _) = await ChatSnapshotData.groupSetup()
        let chat = list.chat(for: .group(id: ChatSnapshotData.groupID, name: "Smoking red"))
        await chat.load()

        let controller = UIHostingController(rootView: KeyboardHarness(chat: chat))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await Task.sleep(for: .milliseconds(800))
        controller.view.layoutIfNeeded()

        let field = try #require(Self.textInput(in: controller.view), "Eingabefeld des Chats nicht gefunden")
        let keyboard = KeyboardFrameRecorder()
        defer { keyboard.stop() }
        #expect(field.becomeFirstResponder())
        // Auf die Tastatur warten (höchstens 3 s) und danach ihre Animation abschließen lassen.
        for _ in 0..<30 where keyboard.frame == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(700))
        controller.view.layoutIfNeeded()

        guard let frame = keyboard.frame, frame.height > 100 else {
            print("KeyboardLayoutTests: keine Bildschirmtastatur im Simulator – Prüfung auf dem Gerät (IPHONE_TEST Fall 7).")
            field.resignFirstResponder()
            return
        }
        let fieldFrame = field.convert(field.bounds, to: window)
        print("KeyboardLayoutTests: Tastatur ab y=\(frame.minY), Eingabefeld endet bei y=\(fieldFrame.maxY).")
        #expect(fieldFrame.maxY <= frame.minY + 1, "Eingabefeld liegt unter der Tastatur")
        #expect(fieldFrame.minY > 0)

        // Tastatur schließen: Eingabe wieder unten über der Tab-Leiste.
        field.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(800))
        controller.view.layoutIfNeeded()
        let closedFrame = field.convert(field.bounds, to: window)
        #expect(closedFrame.maxY > fieldFrame.maxY)
        #expect(closedFrame.maxY < 852 - 34)
    }

    /// Das Textfeld der Eingabeleiste (mehrzeiliges `TextField` → `UITextView`, sonst `UITextField`).
    private static func textInput(in view: UIView) -> UIView? {
        if view is UITextView || view is UITextField { return view }
        for subview in view.subviews {
            if let found = textInput(in: subview) { return found }
        }
        return nil
    }
}

/// Merkt sich den Rahmen der Tastatur aus den Systemmeldungen.
@MainActor
private final class KeyboardFrameRecorder {
    private(set) var frame: CGRect?
    private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            MainActor.assumeIsolated {
                self?.frame = frame
            }
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}

/// Pager mit Chat auf der Social-Seite und Tab-Leiste, die bei offener Tastatur verschwindet – wie `MainTabView`.
private struct KeyboardHarness: View {
    let chat: ChatViewModel

    @State private var selection = 2
    @State private var isKeyboardVisible = false

    var body: some View {
        VStack(spacing: 0) {
            PaceTabPager(tabs: [0, 1, 2, 3], selection: $selection, isPagingEnabled: false, onPositionChange: { _ in }) { tab in
                if tab == 2 {
                    NavigationStack {
                        ChatView(viewModel: chat, onOpenProfile: { _ in })
                    }
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !isKeyboardVisible {
                PaceTabBar(
                    items: [
                        PaceTabItem(value: 0, title: "Home", systemImage: "house", selectedSystemImage: "house.fill"),
                        PaceTabItem(value: 1, title: "Rankings", systemImage: "chart.bar", selectedSystemImage: "chart.bar.fill"),
                        PaceTabItem(value: 2, title: "Social", systemImage: "person.2", selectedSystemImage: "person.2.fill"),
                        PaceTabItem(value: 3, title: "Profil", systemImage: "person", selectedSystemImage: "person.fill"),
                    ],
                    selection: $selection
                )
            }
        }
        .onKeyboardVisibilityChange { isVisible in
            isKeyboardVisible = isVisible
        }
    }
}
