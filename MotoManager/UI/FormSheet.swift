import SwiftUI

/// Delete action offered at the bottom of an edit sheet, behind a
/// confirmation alert.
struct FormSheetDelete {
    /// Alert title, e.g. "Drehmoment löschen?".
    let title: String
    var message: String? = nil
    /// Returns whether the delete went through; the sheet dismisses on `true`.
    let action: () async -> Bool
}

/// The one scaffold every data-entry sheet uses, so they all look and behave
/// alike:
///
/// - inline title, system close (✕) and confirm (✓) toolbar buttons — the
///   iOS 26 sheet idiom, which also leaves the title room instead of
///   truncating it between two text buttons;
/// - confirm is disabled until `canSave`, and turns into a spinner while
///   `onSave` runs;
/// - an optional inline error banner at the top of the form;
/// - an optional delete button behind a confirmation alert;
/// - unsaved changes (`tracked` differs from its first value) block the
///   swipe-down and make ✕ ask before discarding;
/// - success haptic plus a short beat before the sheet dismisses;
/// - a "Fertig" keyboard button, adaptive form width and interactive
///   keyboard dismissal.
///
/// `onSave` returns whether the save landed; on `false` the sheet stays open
/// (the caller shows why via `error`).
struct FormSheet<Content: View>: View {
    let title: String
    var canSave: Bool
    /// Snapshot of the editable values; compared against its first value to
    /// detect unsaved changes.
    var tracked: [AnyHashable] = []
    var error: String? = nil
    var delete: FormSheetDelete? = nil
    /// Sheets with their own keyboard toolbar (field chaining) opt out.
    var showsKeyboardDone = true
    let onSave: () async -> Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var initialTracked: [AnyHashable]?
    @State private var isSaving = false
    @State private var saveSucceeded = false
    @State private var confirmingDiscard = false
    @State private var confirmingDelete = false

    private var isDirty: Bool {
        guard let initialTracked else { return false }
        return initialTracked != tracked
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let error, !error.isEmpty {
                        FormErrorBanner(message: error)
                    }
                    content()
                    if delete != nil {
                        Button(role: .destructive) { confirmingDelete = true } label: {
                            Text("Löschen").frame(maxWidth: .infinity)
                        }
                        .glassActionButton(.danger, in: .roundedRectangle(radius: Theme.Radius.control))
                        .disabled(isSaving)
                        .padding(.top, Theme.Spacing.s)
                    }
                }
                .padding(Theme.Spacing.l)
                .adaptiveFormWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { attemptClose() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                        .accessibilityLabel("Abbrechen")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .accessibilityLabel("Wird gespeichert")
                    } else {
                        Button(role: .confirm) { save() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!canSave || saveSucceeded)
                            .accessibilityLabel("Speichern")
                    }
                }
                if showsKeyboardDone {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fertig") { Self.endEditing() }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saveSucceeded) { _, new in new }
            .confirmationDialog(
                "Änderungen verwerfen?",
                isPresented: $confirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Verwerfen", role: .destructive) { dismiss() }
                Button("Weiter bearbeiten", role: .cancel) { }
            }
            .alert(delete?.title ?? "", isPresented: $confirmingDelete) {
                Button("Abbrechen", role: .cancel) { }
                Button("Löschen", role: .destructive) { performDelete() }
            } message: {
                if let message = delete?.message { Text(message) }
            }
        }
        .interactiveDismissDisabled(isDirty || isSaving)
        .onAppear {
            if initialTracked == nil { initialTracked = tracked }
        }
    }

    private func attemptClose() {
        if isDirty && !saveSucceeded {
            confirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        Self.endEditing()
        isSaving = true
        Task {
            let ok = await onSave()
            isSaving = false
            guard ok else { return }
            withAnimation { saveSucceeded = true }
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }

    private func performDelete() {
        guard let delete else { return }
        isSaving = true
        Task {
            let ok = await delete.action()
            isSaving = false
            if ok { dismiss() }
        }
    }

    static func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }
}

/// Red inline banner for a failed save, shown at the top of the form.
struct FormErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .scaledFont(13, weight: .semibold)
            .foregroundStyle(Theme.Colors.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FormField<EmptyView>.paddingH)
            .padding(.vertical, FormField<EmptyView>.paddingV)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.field)
                    .fill(Theme.Colors.accent.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
    }
}
