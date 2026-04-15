import SwiftUI

struct MotorcycleListView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var viewModel = MotorcycleViewModel()
    @State private var hasAppeared = false
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                LiquidBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.m) {
                        if viewModel.isLoading && viewModel.motorcycles.isEmpty {
                            ForEach(0..<3, id: \.self) { i in
                                ShimmerRow()
                                    .id("skeleton-\(i)")
                            }
                        } else if viewModel.motorcycles.isEmpty && !viewModel.isLoading {
                            EmptyStateView()
                                .padding(.top, 100)
                        } else {
                            ForEach(viewModel.motorcycles) { motorcycle in
                                MotorcycleRowView(motorcycle: motorcycle)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .refreshable {
                    await viewModel.loadMotorcycles()
                }
            }
            .navigationTitle("Your Fleet")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    Task {
                        await viewModel.loadMotorcycles()
                    }
                }
            }
            .onChange(of: viewModel.errorMessage) { newValue in
                if newValue != nil {
                    showError = true
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { 
                    viewModel.errorMessage = nil
                    showError = false
                }
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
        }
    }
}

struct ShimmerRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            RoundedRectangle(cornerRadius: Theme.Radius.l, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 240)
            
            HStack(spacing: Theme.Spacing.xl) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 40, height: 40)
                }
            }
            .padding(.horizontal, Theme.Spacing.s)
        }
        .padding(.horizontal)
        .opacity(0.6)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "bicycle.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No Motorcycles Yet")
                .font(.headline)
            
            Text("Add your first motorcycle to start tracking maintenance and issues.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
    }
}
