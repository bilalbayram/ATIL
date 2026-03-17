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
                    name: "Embed Helper Plist",
                    subpath: "Contents/Library/LaunchDaemons",
                    files: [
                        "SupportingFiles/dev.tuist.ATIL.Helper.plist",
                    ]
                ),
            ],
            scripts: [
                .post(
                    script: """
                    set -eu

                    source_path="${BUILT_PRODUCTS_DIR}/ATILHelper"
                    destination_dir="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Library/HelperTools"
                    destination_path="${destination_dir}/ATILHelper"

                    mkdir -p "$destination_dir"
                    install -m 755 "$source_path" "$destination_path"
                    """,
                    name: "Embed Helper Tool",
                    inputPaths: [
                        "$(BUILT_PRODUCTS_DIR)/ATILHelper",
                    ],
                    outputPaths: [
                        "$(TARGET_BUILD_DIR)/$(WRAPPER_NAME)/Contents/Library/HelperTools/ATILHelper",
                    ],
                    basedOnDependencyAnalysis: true
                ),
            ],
            dependencies: [
                .external(name: "GRDB"),
                .target(name: "ATILHelper"),
            ],
            settings: .settings(base: [
                "MARKETING_VERSION": "1.0.1",
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
