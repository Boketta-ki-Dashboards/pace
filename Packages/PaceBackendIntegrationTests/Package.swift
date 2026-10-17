// swift-tools-version: 6.0
import PackageDescription

// Integrationstests der Supabase-Anbindung (PaceBackend) gegen einen echten, lokalen Supabase-Stack.
// Ohne PACE_SUPABASE_URL / PACE_SUPABASE_PUBLISHABLE_KEY werden alle Tests übersprungen.
// Ausführen: siehe docs/BACKEND.md („Tests“).
let package = Package(
    name: "PaceBackendIntegrationTests",
    platforms: [.macOS(.v14), .iOS(.v17)],
    dependencies: [
        .package(path: "../PaceKit"),
    ],
    targets: [
        .testTarget(
            name: "BackendIntegrationTests",
            dependencies: [
                .product(name: "PaceBackend", package: "PaceKit"),
                .product(name: "PaceCore", package: "PaceKit"),
            ]
        ),
    ]
)
