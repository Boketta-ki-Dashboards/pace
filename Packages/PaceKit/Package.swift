// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PaceKit",
    platforms: [.iOS(.v17)],
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

        // Farben, Typografie, Abstände und wiederverwendbare UI-Komponenten.
        .target(name: "DesignSystem"),

        // Features: jeweils ViewModel (ohne SwiftUI) + Views.
        .target(name: "HealthPermissionFeature", dependencies: ["PaceCore", "DesignSystem"]),
        .target(name: "ActivityFeature", dependencies: ["PaceCore", "DesignSystem"]),
        .target(name: "HomeFeature", dependencies: ["PaceCore", "DesignSystem", "ActivityFeature"]),

        // App-Routing und Zusammenbau der Features.
        .target(
            name: "AppFeature",
            dependencies: ["PaceCore", "DesignSystem", "HealthPermissionFeature", "HomeFeature"]
        ),

        // Test-Doubles, nur von Test-Targets verwendet.
        .target(name: "PaceTestSupport", dependencies: ["PaceCore"], path: "Tests/PaceTestSupport"),

        .testTarget(name: "PaceCoreTests", dependencies: ["PaceCore", "PaceTestSupport"]),
        .testTarget(name: "PaceBackendTests", dependencies: ["PaceBackend", "PaceTestSupport"]),
        .testTarget(
            name: "HealthPermissionFeatureTests",
            dependencies: ["HealthPermissionFeature", "PaceTestSupport"]
        ),
        .testTarget(name: "ActivityFeatureTests", dependencies: ["ActivityFeature", "PaceTestSupport"]),
        .testTarget(name: "HomeFeatureTests", dependencies: ["HomeFeature", "PaceTestSupport"]),
        .testTarget(name: "AppFeatureTests", dependencies: ["AppFeature", "PaceTestSupport"]),
    ]
)
