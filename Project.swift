import ProjectDescription

let project = Project(
    name: "ATIL",
    targets: [
        .target(
            name: "ATIL",
            destinations: .macOS,
            product: .app,
            bundleId: "dev.tuist.ATIL",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "ATIL/Sources",
                "ATIL/Resources",
            ],
            dependencies: []
        ),
        .target(
            name: "ATILTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.ATILTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "ATIL/Tests"
            ],
            dependencies: [.target(name: "ATIL")]
        ),
    ]
)
