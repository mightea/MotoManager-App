import SwiftUI

struct DocumentsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .documents, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)
                
                if viewModel.isLoading && viewModel.documents.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        GlassShimmerRow()
                            .padding(.horizontal, Theme.Spacing.s)
                    }
                } else if viewModel.documents.isEmpty && !viewModel.isLoading {
                    EmptyStateView(title: "No Documents", message: "Upload manuals, registrations, or receipts.", icon: "doc.fill")
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
                        .padding(.horizontal, Theme.Spacing.s)
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.clear)
        .refreshable {
            await viewModel.loadAllData()
        }
    }
}

struct DocumentsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            DocumentsView(viewModel: .mock)
        }
    }
}
