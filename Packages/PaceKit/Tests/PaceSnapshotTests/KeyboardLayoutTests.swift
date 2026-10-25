@testable import DesignSystem
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

    /// Ohne Bildschirmtastatur im Simulator: feste Überdeckung von 300 pt an die Seitenleiste geben. Die Eingabe muss
    /// genau um diese Höhe nach oben rücken – nicht weniger (verdeckt) und nicht mehr (doppelter Abstand).
    @Test func chatInputMovesUpByExactlyTheKeyboardOverlap() async throws {
        let (list, _) = await ChatSnapshotData.groupSetup()
        let chat = list.chat(for: .group(id: ChatSnapshotData.groupID, name: "Smoking red"))
        await chat.load()

        func inputBottom(overlap: CGFloat?) async throws -> (field: CGFloat, pager: CGFloat) {
            let controller = UIHostingController(rootView: KeyboardHarness(chat: chat, overlap: overlap))
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = controller
            window.isHidden = false
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }
            try await Task.sleep(for: .milliseconds(800))
            controller.view.layoutIfNeeded()
            let field = try #require(Self.textInput(in: controller.view))
            let pager = try #require(Self.pager(in: controller.view))
            return (field.convert(field.bounds, to: window).maxY, pager.convert(pager.bounds, to: window).maxY)
        }

        let closed = try await inputBottom(overlap: nil)
        let open = try await inputBottom(overlap: 300)
        print("KeyboardLayoutTests: Eingabe endet bei \(closed.field) (ohne) bzw. \(open.field) (mit 300 pt), Seitenleiste bis \(open.pager).")
        #expect(abs((closed.field - open.field) - 300) < 2, "Die Eingabe rückt nicht genau um die Tastaturhöhe nach oben")
        #expect(open.field <= open.pager - 300 + 1)

        // Antwortvorschau + Tastatur: Die Vorschau sitzt über der Eingabe – beide bleiben über der Tastatur, die
        // Eingabe rückt um dieselbe Höhe nach oben wie ohne Vorschau.
        let message = try #require(chat.messages.last)
        chat.startReply(to: message)
        defer { chat.cancelReply() }
        #expect(chat.replyingTo == message)
        let replyClosed = try await inputBottom(overlap: nil)
        let replyOpen = try await inputBottom(overlap: 300)
        print("KeyboardLayoutTests: mit Antwortvorschau \(replyClosed.field) (ohne) bzw. \(replyOpen.field) (mit 300 pt).")
        #expect(abs((replyClosed.field - replyOpen.field) - 300) < 2, "Mit Antwortvorschau rückt die Eingabe nicht genau um die Tastaturhöhe")
        #expect(replyOpen.field <= replyOpen.pager - 300 + 1)
    }

    private static func pager(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, scrollView.contentSize.width > scrollView.bounds.width + 1 {
            return scrollView
        }
        for subview in view.subviews {
            if let found = pager(in: subview) { return found }
        }
        return nil
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
    var overlap: CGFloat?

    @State private var selection = 2
    @State private var isKeyboardVisible = false

    private var pager: some View {
        var pager = PaceTabPager(tabs: [0, 1, 2, 3], selection: $selection, isPagingEnabled: false, onPositionChange: { _ in }) { tab in
            if tab == 2 {
                NavigationStack {
                    ChatView(viewModel: chat, onOpenProfile: { _ in })
                }
            } else {
                Color.clear
            }
        }
        pager.keyboardOverlapForTesting = overlap
        return pager
    }

    var body: some View {
        VStack(spacing: 0) {
            pager
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
