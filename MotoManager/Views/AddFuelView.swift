import SwiftUI

struct AddFuelView: View {
    @ObservedObject var viewModel: MotorcycleDetailViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var odo: String = ""
    @State private var amount: String = ""
    @State private var cost: String = ""
    @State private var date = Date()
    
    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackgroundView().ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.l) {
                    VStack(spacing: Theme.Spacing.m) {
                        QuickInputField(label: "Odometer (km)", text: $odo, icon: "gauge.with.dots", keyboardType: .numberPad)
                        QuickInputField(label: "Amount (Liters)", text: $amount, icon: "fuelpump.fill", keyboardType: .decimalPad)
                        QuickInputField(label: "Total Cost", text: $cost, icon: "eurosign.circle.fill", keyboardType: .decimalPad)
                        
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(Theme.Radius.m)
                    }
                    .padding()
                    
                    Button(action: {
                        Task {
                            let odoInt = Int(odo) ?? 0
                            let amountDouble = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0.0
                            let costDouble = Double(cost.replacingOccurrences(of: ",", with: ".")) ?? 0.0
                            
                            if await viewModel.addFuelRecord(odo: odoInt, amount: amountDouble, cost: costDouble, date: date) {
                                dismiss()
                            }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Save Fuel Record")
                        }
                    }
                    .buttonStyle(ModernButtonStyle(isLoading: viewModel.isLoading))
                    .disabled(odo.isEmpty || amount.isEmpty || cost.isEmpty || viewModel.isLoading)
                    .padding()
                    
                    Spacer()
                }
                .navigationTitle("Add Fuel")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}

struct QuickInputField: View {
    let label: String
    @Binding var text: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            HStack {
                Image(systemName: icon)
                    .foregroundColor(Theme.Colors.primary)
                TextField("", text: $text)
                    .keyboardType(keyboardType)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
