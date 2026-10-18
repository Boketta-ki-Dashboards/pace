// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaceKit",
    // macOS nur, damit PaceCore und PaceBackend für die Integrationstests auf dem Mac bauen (die App ist iOS-only).
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Wird von der App eingebunden (Routing + Features).
        .library(name: "AppFeature", targets: ["AppFeature"]),
        // Konkrete HealthKit-Anbindung, nur im Composition Root der App verwendet.
        .library(name: "PaceHealth", targets: ["PaceHealth"]),
        // Konkrete Supabase-Anbindung, nur im Composition Root der App verwendet.
        .library(name: "PaceBackend", targets: ["PaceBackend"]),
        // Für spätere Targets (z. B. Widget-Extension) separat verfügbar.
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        // Offizieller Supabase-Client. Verwendet werden nur Auth und PostgREST (kein Realtime/Storage/Functions).
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.4"),
    ],
    targets: [
        // Domänenmodelle, Service-Protokolle und Use Cases. Nur Foundation.
        .target(name: "PaceCore"),

        // HealthKit-Implementierung der Protokolle aus PaceCore.
        .target(name: "PaceHealth", dependencies: ["PaceCore"]),

        // Supabase-Implementierung der Protokolle aus PaceCore.
        .target(
            name: "PaceBackend",
            dependencies: [
                "PaceCore",
                .product(name: "Auth", package: "supabase-swift"),
                .product(name: "PostgREST", package: "supabase-swift"),
            ]
        ),

        // Farben, Typografie, Abstände, Wortmarke und wiederverwendbare UI-Komponenten.
        .target(name: "DesignSystem", resources: [.process("Resources")]),

        // Features: jeweils ViewModel (ohne SwiftUI) + Views.
        .target(name: "HealthPermissionFeature", dependencies: ["PaceCore", "DesignSystem"]),
        .target(name: "ActivityFeature", dependencies: ["PaceCore", "DesignSystem"]),
        .target(name: "HomeFeature", dependencies: ["PaceCore", "DesignSystem", "ActivityFeature", "SocialFeature"]),
        .target(name: "RegionFeature", dependencies: ["PaceCore", "DesignSystem"]),
        .target(name: "OnboardingFeature", dependencies: ["PaceCore", "DesignSystem", "RegionFeature"]),
        .target(name: "LeaderboardFeature", dependencies: ["PaceCore", "DesignSystem"]),
        .target(name: "ProfileFeature", dependencies: ["PaceCore", "DesignSystem", "RegionFeature", "ActivityFeature"]),
        .target(name: "SocialFeature", dependencies: ["PaceCore", "DesignSystem"]),

        // App-Routing, Tab-Navigation und Zusammenbau der Features.
        .target(
            name: "AppFeature",
            dependencies: [
                "PaceCore", "DesignSystem", "HealthPermissionFeature", "ActivityFeature", "HomeFeature",
                "OnboardingFeature", "LeaderboardFeature", "ProfileFeature", "SocialFeature",
            ]
        ),

        // Test-Doubles, nur von Test-Targets verwendet.
        .target(name: "PaceTestSupport", dependencies: ["PaceCore"], path: "Tests/PaceTestSupport"),

        .testTarget(name: "PaceCoreTests", dependencies: ["PaceCore", "PaceTestSupport"]),
        .testTarget(name: "PaceBackendTests", dependencies: ["PaceBackend", "PaceTestSupport"]),
        // Nur auf Apple-Plattformen (HealthKit); läuft in der CI im iOS-Simulator.
        .testTarget(name: "PaceHealthTests", dependencies: ["PaceHealth", "PaceCore"]),
        .testTarget(
            name: "HealthPermissionFeatureTests",
            dependencies: ["HealthPermissionFeature", "PaceTestSupport"]
        ),
        .testTarget(name: "ActivityFeatureTests", dependencies: ["ActivityFeature", "PaceTestSupport"]),
        .testTarget(name: "HomeFeatureTests", dependencies: ["HomeFeature", "ActivityFeature", "SocialFeature", "PaceTestSupport"]),
        .testTarget(name: "RegionFeatureTests", dependencies: ["RegionFeature", "PaceTestSupport"]),
        .testTarget(name: "OnboardingFeatureTests", dependencies: ["OnboardingFeature", "PaceTestSupport"]),
        .testTarget(name: "LeaderboardFeatureTests", dependencies: ["LeaderboardFeature", "PaceTestSupport"]),
        .testTarget(name: "ProfileFeatureTests", dependencies: ["ProfileFeature", "ActivityFeature", "PaceTestSupport"]),
        .testTarget(name: "SocialFeatureTests", dependencies: ["SocialFeature", "PaceTestSupport"]),
        // Rendert Screens als Bilder für die visuelle Kontrolle (nur mit PACE_SNAPSHOT_DIR, siehe ios.yml).
        .testTarget(
            name: "PaceSnapshotTests",
            dependencies: [
                "PaceCore", "DesignSystem", "ActivityFeature", "HomeFeature", "LeaderboardFeature",
                "ProfileFeature", "SocialFeature", "PaceTestSupport",
            ]
        ),
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature", "HomeFeature", "OnboardingFeature", "PaceTestSupport"]),
    ]
)
