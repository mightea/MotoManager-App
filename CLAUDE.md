# Project: MotoManager

**MotoManager** is a SwiftUI iOS app for managing a personal motorcycle fleet — fuel logs and consumption analytics, service/maintenance records, torque specs, and a document vault. It is backed by a private API at `https://moto-api.herrmann.ltd` (JWT auth, with passkey/WebAuthn support).

## Quick Reference

- **Platform**: iOS 17+ / macOS 14+
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Minimum Deployment**: iOS 17.0
- **Package Manager**: Swift Package Manager

## XcodeBuildMCP Integration

**IMPORTANT**: This project uses XcodeBuildMCP for all Xcode operations.

- Build: `mcp__xcodebuildmcp__build_sim_name_proj`
- Test: `mcp__xcodebuildmcp__test_sim_name_proj`
- Clean: `mcp__xcodebuildmcp__clean`

## Project Structure

MVVM. Source layout under `MotoManager/`:

```
MotoManager/
├── MotoManagerApp.swift     # @main entry point — minimal
├── ContentView.swift        # auth gate + fleet load orchestration
├── Models/                  # Codable structs
├── ViewModels/              # @MainActor ObservableObjects
├── Views/                   # SwiftUI screens
├── Networking/              # NetworkManager + KeychainHelper
└── UI/                      # design tokens + reusable visual primitives
```

## Coding Standards

### Swift Style

- Use Swift 6 strict concurrency
- Prefer `@Observable` over `ObservableObject`
- Use `async/await` for all async operations
- Follow Apple's Swift API Design Guidelines
- Use `guard` for early exits
- Prefer value types (structs) over reference types (classes)

### SwiftUI Patterns

- Extract views when they exceed 100 lines
- Use `@State` for local view state only
- Use `@Environment` for dependency injection
- Prefer `NavigationStack` over deprecated `NavigationView`
- Use `@Bindable` for bindings to @Observable objects

### Navigation Pattern

```swift
// Use NavigationStack with type-safe routing
enum Route: Hashable {
    case detail(Item)
    case settings
}

NavigationStack(path: $router.path) {
    ContentView()
        .navigationDestination(for: Route.self) { route in
            // Handle routing
        }
}

## Quick Reference
- **Platform**: iOS 17+ / macOS 14+
- **Language**: Swift 6.0
- **UI Framework**: SwiftUI
- **Architecture**: MVVM with @Observable
- **Minimum Deployment**: iOS 17.0
- **Package Manager**: Swift Package Manager

## XcodeBuildMCP Integration
**IMPORTANT**: This project uses XcodeBuildMCP for all Xcode operations.
- Build: `mcp__xcodebuildmcp__build_sim_name_proj`
- Test: `mcp__xcodebuildmcp__test_sim_name_proj`
- Clean: `mcp__xcodebuildmcp__clean`

## Project Structure
```

## Coding Standards

### Swift Style

- Use Swift 6 strict concurrency
- Prefer `@Observable` over `ObservableObject`
- Use `async/await` for all async operations
- Follow Apple's Swift API Design Guidelines
- Use `guard` for early exits
- Prefer value types (structs) over reference types (classes)

### SwiftUI Patterns

- Extract views when they exceed 100 lines
- Use `@State` for local view state only
- Use `@Environment` for dependency injection
- Prefer `NavigationStack` over deprecated `NavigationView`
- Use `@Bindable` for bindings to @Observable objects

### Navigation Pattern

```swift
// Use NavigationStack with type-safe routing
enum Route: Hashable {
    case detail(Item)
    case settings
}

NavigationStack(path: $router.path) {
    ContentView()
        .navigationDestination(for: Route.self) { route in
            // Handle routing
        }
}
```

### Error Handling

```swift
// Always use typed errors
enum AppError: LocalizedError {
    case networkError(underlying: Error)
    case validationError(message: String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error): return error.localizedDescription
        case .validationError(let msg): return msg
        }
    }
}
```

## Testing Requirements

- Unit tests for all ViewModels
- UI tests for critical user flows
- Use Swift Testing framework (`@Test`, `#expect`)
- Minimum 80% code coverage for business logic

## DO NOT

- Write UITests during scaffolding phase
- Use deprecated APIs (UIKit when SwiftUI suffices)
- Create massive monolithic views
- Use force unwrapping (`!`) without justification
- Ignore Swift 6 concurrency warnings

## Planning Workflow

When starting new features:

1. Read the PRD from `docs/PRD.md`
2. Create feature spec in `docs/specs/[feature-name].md`
3. Use `ultrathink` for architectural decisions
4. Use Plan Mode (`Shift+Tab`) for implementation strategy
5. Implement incrementally with tests

## Memory Imports

@import docs/PRD.md
@import docs/ARCHITECTURE.md
@import docs/ROADMAP.md

```

### Nested CLAUDE.md for Feature Directories

Create `.claude/CLAUDE.md` or `Features/[FeatureName]/CLAUDE.md`:

```markdown
# [Feature Name] Module

## Purpose
[Description of what this feature does]

## Architecture
- Uses MVVM with @Observable ViewModels
- Parent stores create child stores for modal presentations

## Navigation Pattern
### Sheet-Based Navigation
**Pattern**: Parent stores create optional child stores for modal presentations
**Rules**:
1. Parent ViewModel holds `@Published var childViewModel: ChildViewModel?`
2. View observes and presents sheet when non-nil
3. Dismissal sets childViewModel to nil

### Example
```swift
@Observable
final class ParentViewModel {
    var detailViewModel: DetailViewModel?
    
    func showDetail(for item: Item) {
        detailViewModel = DetailViewModel(item: item)
    }
}
```

## Testing

Run tests: `mcp__xcodebuildmcp__swift_package_test`

```

---

## 4. PRD-Driven Development Workflow

### Directory Structure for PRD Workflow

```

docs/
├── PRD.md                      # Main Product Requirements Document
├── ARCHITECTURE.md             # System architecture decisions
├── specs/                      # Feature specifications
│   └── template.md
└── tasks/                      # Task breakdowns
    ├── 000-sample.md
    └── [feature]-tasks.md

```

### PRD Template (`docs/PRD.md`)

```markdown
# Product Requirements Document: [App Name]

## Executive Summary
[Brief description of the product and its primary value proposition]

## Problem Statement
[What problem does this solve? Who experiences this problem?]

## Target Users
- **Primary**: [Description]
- **Secondary**: [Description]

## Success Metrics
| Metric | Target | Measurement |
|--------|--------|-------------|
| User Retention | 40% D7 | Analytics |
| App Rating | 4.5+ | App Store |
| Crash-Free Rate | 99.5% | Crashlytics |

## Core Features

### Feature 1: [Name]
**Priority**: P0 (Must Have)
**Description**: [Detailed description]
**User Stories**:
- As a [user type], I want [action] so that [benefit]

**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2

**Technical Requirements**:
- iOS 17+ required
- Offline support needed
- Data persistence via SwiftData

### Feature 2: [Name]
[Continue pattern...]

## Non-Functional Requirements
- **Performance**: App launch < 2s, smooth 60fps scrolling
- **Accessibility**: WCAG 2.1 AA compliance
- **Localization**: English (primary), [other languages]
- **Security**: Keychain for credentials, certificate pinning

## Out of Scope (v1.0)
- [Feature explicitly not included]

## Technical Constraints
- Swift 6.0+ with strict concurrency
- SwiftUI-only (no UIKit unless necessary)
- SwiftData for persistence
- Minimum iOS 17.0

