//
//  InlineAssist.swift
//  Keystone
//
//  Select → describe the change → review the proposal → accept or reject.
//  The host supplies the model call; Keystone owns the UI and the undo story.
//

import SwiftUI

/// What the host gets when the user asks for an inline edit.
public struct InlineAssistRequest: Sendable {
    /// The user's instruction.
    public let instruction: String
    /// The text to rewrite: the selection, or the caret's line when nothing is selected.
    public let selectedText: String
    /// Where `selectedText` sits, in UTF-16 units.
    public let selectionRange: NSRange
    public let language: KeystoneLanguage
    /// Up to 2,000 characters before and after the selection, for context.
    public let contextBefore: String
    public let contextAfter: String
    /// UTF-16 length of the whole document.
    public let documentLength: Int

    public init(instruction: String, selectedText: String, selectionRange: NSRange, language: KeystoneLanguage, contextBefore: String, contextAfter: String, documentLength: Int) {
        self.instruction = instruction
        self.selectedText = selectedText
        self.selectionRange = selectionRange
        self.language = language
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.documentLength = documentLength
    }
}

/// Returns the replacement for `request.selectedText`. Throw to show an error.
public typealias InlineAssistHandler = @MainActor @Sendable (InlineAssistRequest) async throws -> String

struct ProposedEdit: Equatable {
    var range: NSRange
    var originalText: String
    var replacementText: String
}

enum InlineAssistPhase: Equatable {
    case idle
    case prompting
    case running
    case reviewing(ProposedEdit)
    case failed(String)
}

/// The bar under the toolbar that drives the inline-assist flow.
struct InlineAssistBar: View {
    let phase: InlineAssistPhase
    @Binding var instruction: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void
    let onRetry: () -> Void

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(.accentColor)
            switch phase {
            case .idle:
                EmptyView()
            case .prompting:
                TextField(String(localized: "Describe the change…", bundle: .module), text: $instruction)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit(onSubmit)
                    #if os(iOS)
                    .autocapitalization(.sentences)
                    #endif
                Button(String(localized: "Go", bundle: .module), action: onSubmit)
                    .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                closeButton(onCancel)
            case .running:
                ProgressView().controlSize(.small)
                Text("Working…", bundle: .module).foregroundColor(.secondary)
                Spacer()
                Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                    .keyboardShortcut(.cancelAction)
            case .reviewing:
                Text("Review the proposed change", bundle: .module)
                Spacer()
                Button(String(localized: "Reject", bundle: .module), action: onReject)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Try Again", bundle: .module), action: onRetry)
                Button(String(localized: "Accept", bundle: .module), action: onAccept)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            case .failed(let message):
                Text(message).foregroundColor(.red).lineLimit(2)
                Spacer()
                Button(String(localized: "Try Again", bundle: .module), action: onRetry)
                closeButton(onCancel)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.keystoneStatusBar)
        .onAppear { isFieldFocused = true }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .prompting { isFieldFocused = true }
        }
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
    }
}
