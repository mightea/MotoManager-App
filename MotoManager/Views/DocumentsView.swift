import SwiftUI

struct DocumentsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                if viewModel.documents.isEmpty && !viewModel.isLoading {
                    EmptyStateView(title: "No Documents", message: "Upload manuals, registrations, or receipts.")
                        .padding(.top, 100)
                } else {
                    ForEach(viewModel.documents) { doc in
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .font(.title2)
                                .foregroundColor(Theme.Colors.primary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(doc.title)
                                    .font(.headline)
                                Text("Added on \(doc.createdAt.prefix(10))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(Theme.Radius.m)
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, 100)
        }
        .refreshable {
            await viewModel.loadAllData()
        }
    }
}
