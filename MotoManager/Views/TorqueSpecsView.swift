import SwiftUI

struct TorqueSpecsView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.m) {
                MotorcycleSummaryHeader(motorcycle: viewModel.motorcycle, type: .torque, viewModel: viewModel)
                    .ignoresSafeArea(edges: .top)
                
                if viewModel.isLoading && viewModel.torqueSpecs.isEmpty {
                    ForEach(0..<5, id: \.self) { _ in
                        GlassShimmerRow()
                            .padding(.horizontal, Theme.Spacing.s)
                    }
                } else if viewModel.torqueSpecs.isEmpty && !viewModel.isLoading {
                    EmptyStateView(title: "No Torque Specs", message: "Specifications for this model aren't available yet.")
                        .padding(.top, 100)
                } else {
                    ForEach(viewModel.torqueSpecs) { spec in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(spec.name)
                                    .font(.headline)
                                Text(spec.category)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(Int(spec.torque)) Nm")
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(Theme.Colors.primary)
                                if let tool = spec.toolSize {
                                    Text(tool)
                                        .font(.system(size: 10, weight: .heavy))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
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

struct TorqueSpecsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            TorqueSpecsView(viewModel: .mock)
        }
    }
}
