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
            copyFiles: [
                .wrapper(
                    name: "Embed Helper Tool",
                    subpath: "Contents/Library/HelperTools",
                    files: [
                        "$(BUILT_PRODUCTS_DIR)/ATILHelper",
                    ]
                ),
                .wrapper(
                    name: "Embed Helper Plist",
                    subpath: "Contents/Library/LaunchDaemons",
                    files: [
                        "SupportingFiles/dev.tuist.ATIL.Helper.plist",
                    ]
                ),
            ],
            dependencies: [
                .external(name: "GRDB"),
                .target(name: "ATILHelper"),
            ],
            settings: .settings(base: [
                "MARKETING_VERSION": "1.0.0",
                "CURRENT_PROJECT_VERSION": "1",
            ])
        ),
        .target(
            name: "ATILHelper",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "dev.tuist.ATIL.Helper",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            sources: [
                "ATILHelper/Sources/**",
            ],
            settings: .settings(base: [
                "PRODUCT_NAME": "ATILHelper",
                "CODE_SIGN_STYLE": "Automatic",
            ])
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
