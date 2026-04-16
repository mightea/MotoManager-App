import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var selectedBaseURL = NetworkManager.shared.baseURL
    
    let environments = [
        ("Production", "https://moto-api.herrmann.ltd"),
        ("Development", "http://localhost:3001")
    ]
    
    var body: some View {
        ZStack {
            LiquidBackgroundView().ignoresSafeArea()
            
            List {
                Section(header: Text("Environment")) {
                    Picker("Backend", selection: $selectedBaseURL) {
                        ForEach(environments, id: \.1) { name, url in
                            Text(name).tag(url)
                        }
                    }
                    .onChange(of: selectedBaseURL) { oldValue, newValue in
                        NetworkManager.shared.baseURL = newValue
                        authVM.resetSession()
                    }
                    
                    Text(selectedBaseURL)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Account")) {
                    Button(action: {
                        authVM.logout()
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text("Logout")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section(header: Text("App Information")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .scrollContentBackground(.hidden)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AuthViewModel())
    }
}
