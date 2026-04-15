import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    
    var body: some View {
        List {
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
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView().environmentObject(AuthViewModel())
    }
}
