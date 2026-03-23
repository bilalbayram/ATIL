import Foundation
import ProjectDescription

struct AppVersionSettings {
    let marketingVersion: String
    let currentProjectVersion: String
}

func loadAppVersionSettings(from relativePath: String = "Config/Version.xcconfig") -> AppVersionSettings {
    let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fileURL = rootURL.appendingPathComponent(relativePath)

    guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
        fatalError("Unable to read version settings from \(relativePath)")
    }

    var values: [String: String] = [:]

    for rawLine in contents.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("//"), !line.hasPrefix("#") else {
            continue
        }

        let components = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count == 2 else {
            fatalError("Invalid version settings line: \(rawLine)")
        }

        values[components[0]] = components[1]
    }

    guard let marketingVersion = values["MARKETING_VERSION"],
          let currentProjectVersion = values["CURRENT_PROJECT_VERSION"] else {
        fatalError("Config/Version.xcconfig must define MARKETING_VERSION and CURRENT_PROJECT_VERSION")
    }

    return AppVersionSettings(
        marketingVersion: marketingVersion,
        currentProjectVersion: currentProjectVersion
    )
}

let appVersionSettings = loadAppVersionSettings()

let project = Project(
    name: "ATIL",
    targets: [
        .target(
            name: "ATIL",
            destinations: .macOS,
            product: .app,
            bundleId: "com.bilalbayram.ATIL",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                "SUFeedURL": "https://raw.githubusercontent.com/bilalbayram/ATIL/main/appcast.xml",
                "SUPublicEDKey": "$(SPARKLE_ED_PUBLIC_KEY)",
            ]),
            buildableFolders: [
                "ATIL/Sources",
                "ATIL/Resources",
            ],
            copyFiles: [
                .wrapper(
                    name: "Embed Helper Plist",
                    subpath: "Contents/Library/LaunchDaemons",
                    files: [
                        "SupportingFiles/com.bilalbayram.ATIL.Helper.plist",
                    ]
                ),
            ],
            entitlements: .dictionary([
                "com.apple.security.network.client": .boolean(true),
            ]),
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
                .external(name: "Sparkle"),
                .target(name: "ATILHelper"),
            ],
            settings: .settings(base: [
                "MARKETING_VERSION": .string(appVersionSettings.marketingVersion),
                "CURRENT_PROJECT_VERSION": .string(appVersionSettings.currentProjectVersion),
                "SPARKLE_ED_PUBLIC_KEY": .string("1+6/4ww0jBVqZ9B2nKhlaXTC7xBJKtmkMNEDONVUnyg="),
            ])
        ),
        .target(
            name: "ATILHelper",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.bilalbayram.ATIL.Helper",
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
            bundleId: "com.bilalbayram.ATILTests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "ATIL/Tests"
            ],
            dependencies: [.target(name: "ATIL")]
        ),
    ]
)
