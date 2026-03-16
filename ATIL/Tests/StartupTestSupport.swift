import Foundation
@testable import ATIL

func makeStartupAppIdentity(
    displayName: String = "Steam",
    bundleIdentifier: String? = "com.valvesoftware.steam",
    teamIdentifier: String? = "VALVE123",
    bundlePath: String? = "/Applications/Steam.app"
) -> StartupAppIdentity {
    StartupAppIdentity(
        displayName: displayName,
        bundleIdentifier: bundleIdentifier,
        teamIdentifier: teamIdentifier,
        bundlePath: bundlePath
    )
}

func makeStartupItem(
    id: String = "item-1",
    kind: StartupItemKind = .launchAgent,
    scope: StartupItemScope = .user,
    state: StartupItemState = .enabled,
    label: String? = "com.valvesoftware.steamclean",
    plistPath: String? = "/Users/test/Library/LaunchAgents/com.valvesoftware.steamclean.plist",
    executablePath: String? = "/Users/test/Library/Application Support/Steam/SteamApps/steamclean",
    app: StartupAppIdentity = makeStartupAppIdentity(),
    matchedProcessIDs: [pid_t] = [],
    matchedProcessNames: [String] = []
) -> StartupItem {
    StartupItem(
        id: id,
        kind: kind,
        scope: scope,
        state: state,
        label: label,
        plistPath: plistPath,
        executablePath: executablePath,
        programArguments: executablePath.map { [$0] } ?? [],
        domain: scope == .system ? "system" : "gui/\(getuid())",
        app: app,
        attributionConfidence: .high,
        attributionSources: ["test"],
        matchedProcessIDs: matchedProcessIDs,
        matchedProcessNames: matchedProcessNames
    )
}

func makeLaunchdJob(
    label: String = "com.valvesoftware.steamclean",
    plistPath: String = "/Users/test/Library/LaunchAgents/com.valvesoftware.steamclean.plist",
    domain: String = "gui/501",
    programPath: String? = "/Users/test/Library/Application Support/Steam/SteamApps/steamclean",
    keepAlive: Bool = false,
    runAtLoad: Bool = true
) -> LaunchdJobInfo {
    LaunchdJobInfo(
        label: label,
        plistPath: plistPath,
        domain: domain,
        programPath: programPath,
        programArguments: programPath.map { [$0] },
        keepAlive: keepAlive,
        runAtLoad: runAtLoad
    )
}

func makeProcess(
    pid: pid_t = 42,
    name: String = "steamclean",
    executablePath: String? = "/Users/test/Library/Application Support/Steam/SteamApps/steamclean",
    bundleIdentifier: String? = "com.valvesoftware.steam",
    bundlePath: String? = "/Applications/Steam.app",
    launchdJob: LaunchdJobInfo? = nil
) -> ATILProcess {
    ATILProcess(
        identity: ProcessIdentity(pid: pid, startTime: .distantPast),
        pid: pid,
        ppid: 1,
        uid: getuid(),
        gid: getgid(),
        name: name,
        executablePath: executablePath,
        startTime: .distantPast,
        residentMemory: 1_024,
        virtualMemory: 4_096,
        cpuTimeUser: 1,
        cpuTimeSystem: 0.5,
        cpuPercent: 3.0,
        threadCount: 2,
        niceValue: 0,
        processState: .running,
        isOrphaned: false,
        parentAlive: true,
        hasTTY: false,
        hasSockets: false,
        hasOwningApp: bundlePath != nil,
        bundleIdentifier: bundleIdentifier,
        bundlePath: bundlePath,
        owningAppBundleIdentifier: bundleIdentifier,
        owningAppBundlePath: bundlePath,
        category: .healthy,
        classificationReasons: [],
        lastSeen: Date(),
        idleSince: nil,
        launchdJob: launchdJob,
        appIcon: nil
    )
}
