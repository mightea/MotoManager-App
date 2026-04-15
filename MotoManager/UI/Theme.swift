import SwiftUI

enum Theme {
    enum Colors {
        static let primary = Color.blue
        static let accent = Color.orange
        static let background = Color(UIColor.systemBackground)
        static let secondaryBackground = Color(UIColor.secondarySystemBackground)
        static let cardBackground = Color(UIColor.tertiarySystemBackground)
        
        static let glassBackground = Color.white.opacity(0.05)
        static let glassBorder = Color.white.opacity(0.2)
        
        static let gradientStart = Color.blue
        static let gradientEnd = Color(red: 0.2, green: 0.4, blue: 0.9)
        
        static let meshColors: [Color] = [
            Color.blue.opacity(0.3),
            Color.purple.opacity(0.2),
            Color.cyan.opacity(0.2),
            Color.blue.opacity(0.1)
        ]
    }
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }
    
    enum Radius {
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
        static let xl: CGFloat = 30
    }
}

struct ModernButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Theme.Colors.gradientStart, Theme.Colors.gradientEnd]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    
                    if configuration.isPressed {
                        Color.black.opacity(0.1)
                    }
                }
            )
            .cornerRadius(Theme.Radius.m)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
            .opacity(isLoading ? 0.8 : 1.0)
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(Theme.Radius.m)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
    }
}
