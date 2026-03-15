import AppKit
import Darwin

struct ProcessEnumerator: Sendable {

    // MARK: - PID Enumeration

    func listAllPIDs() -> [pid_t] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        let bufferSize = Int(estimatedCount) * 2
        var pids = [pid_t](repeating: 0, count: bufferSize)
        let byteCount = proc_listallpids(&pids, Int32(bufferSize * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }

        let actualCount = Int(byteCount)
        return Array(pids.prefix(actualCount)).filter { $0 > 0 }
    }

    // MARK: - BSD Info

    func getBSDInfo(pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    // MARK: - Task Info

    func getTaskInfo(pid: pid_t) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    // MARK: - Executable Path

    func getPath(pid: pid_t) -> String? {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { buffer.deallocate() }
        let result = proc_pidpath(pid, buffer, UInt32(MAXPATHLEN))
        guard result > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Running Application Map

    func buildRunningAppMap() -> [pid_t: NSRunningApplication] {
        var map: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            map[app.processIdentifier] = app
        }
        return map
    }

    func buildRunningAppBundlePaths() -> Set<String> {
        Set(
            NSWorkspace.shared.runningApplications.compactMap { app in
                app.bundleURL?.path
            }
        )
    }

    // MARK: - Bundle Resolution

    func nearestBundlePath(forExecutablePath path: String) -> String? {
        ProcessHeuristics.nearestBundlePath(forExecutablePath: path)
    }

    func owningAppBundlePath(forExecutablePath path: String) -> String? {
        ProcessHeuristics.owningAppBundlePath(forExecutablePath: path)
    }

    // MARK: - Build Process

    struct EnumerationContext {
        let now: Date
        let currentUID: uid_t
        let alivePIDs: Set<pid_t>
        let previousIdleTimes: [ProcessIdentity: Date]
        let previousCPUTimes: [ProcessIdentity: TimeInterval]
        let previousSeenTimes: [ProcessIdentity: Date]
        let launchdMap: [String: LaunchdJobInfo]
    }

    func hasSocketFDs(pid: pid_t) -> Bool {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return false }

        let fdInfoSize = Int32(MemoryLayout<proc_fdinfo>.size)
        let count = Int(bufferSize / fdInfoSize)
        guard count > 0 else { return false }

        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard actualSize > 0 else { return false }

        let actualCount = Int(actualSize / fdInfoSize)
        return fds.prefix(actualCount).contains { fd in
            fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET)
        }
    }

    func buildProcess(
        pid: pid_t,
        appMap: [pid_t: NSRunningApplication],
        runningAppBundlePaths: Set<String>,
        context: EnumerationContext
    ) -> ATILProcess? {
        guard let bsdInfo = getBSDInfo(pid: pid) else { return nil }

        let name: String = {
            if let app = appMap[pid], let localizedName = app.localizedName, !localizedName.isEmpty {
                return localizedName
            }
            let bsdName = stringFromTuple(bsdInfo.pbi_name, maxLength: Int(MAXCOMLEN))
            if !bsdName.isEmpty { return bsdName }
            let commName = stringFromTuple(bsdInfo.pbi_comm, maxLength: Int(MAXCOMLEN))
            return commName.isEmpty ? "Unknown" : commName
        }()

        let startTime = Date(timeIntervalSince1970: TimeInterval(bsdInfo.pbi_start_tvsec))
        let identity = ProcessIdentity(pid: pid, startTime: startTime)

        let path = getPath(pid: pid)
        let taskInfo = getTaskInfo(pid: pid)

        let ppid = pid_t(bsdInfo.pbi_ppid)
        let uid = bsdInfo.pbi_uid
        let gid = bsdInfo.pbi_gid
        let hasTTY = bsdInfo.e_tdev != 0 && bsdInfo.e_tdev != UInt32(bitPattern: -1)
        let hasSockets = hasSocketFDs(pid: pid)

        let processState: ProcessState = {
            let status = bsdInfo.pbi_status
            switch status {
            case UInt32(SRUN): return .running
            case UInt32(SSLEEP): return .sleeping
            case UInt32(SSTOP): return .suspended
            case UInt32(SZOMB): return .zombie
            default: return .unknown
            }
        }()

        let residentMemory = taskInfo.map { UInt64($0.pti_resident_size) } ?? 0
        let virtualMemory = taskInfo.map { UInt64($0.pti_virtual_size) } ?? 0
        let cpuTimeUser = taskInfo.map {
            TimeInterval($0.pti_total_user) / 1_000_000_000
        } ?? 0
        let cpuTimeSystem = taskInfo.map {
            TimeInterval($0.pti_total_system) / 1_000_000_000
        } ?? 0
        let threadCount = taskInfo.map { Int32($0.pti_threadnum) } ?? 0
        let niceValue = Int32(bsdInfo.pbi_nice)

        let parentAlive = context.alivePIDs.contains(ppid)

        // Bundle resolution
        let runningApp = appMap[pid]
        let concreteBundlePath = path.flatMap(nearestBundlePath(forExecutablePath:))
        let concreteBundle = concreteBundlePath.flatMap(Bundle.init(path:))
        let owningAppPath = runningApp?.bundleURL?.path
            ?? path.flatMap(owningAppBundlePath(forExecutablePath:))
        let owningAppBundle = owningAppPath.flatMap(Bundle.init(path:))
        let bundleIdentifier = runningApp?.bundleIdentifier
            ?? concreteBundle?.bundleIdentifier
        let bundlePath = runningApp?.bundleURL?.path
            ?? concreteBundlePath
        let owningAppBundleIdentifier = runningApp?.bundleIdentifier
            ?? owningAppBundle?.bundleIdentifier
        let hasOwningApp = owningAppPath.map { runningAppBundlePaths.contains($0) } ?? false

        let launchdJob = path.flatMap { context.launchdMap[$0] }
        let isOrphaned = ProcessHeuristics.isLikelyOrphaned(
            ppid: ppid,
            launchdJob: launchdJob,
            owningAppBundlePath: owningAppPath,
            owningAppBundleIdentifier: owningAppBundleIdentifier,
            bundlePath: bundlePath,
            bundleIdentifier: bundleIdentifier,
            executablePath: path
        )

        // App icon
        let appIcon: NSImage? = {
            if let icon = runningApp?.icon { return icon }
            if let owningAppPath {
                return NSWorkspace.shared.icon(forFile: owningAppPath)
            }
            if let p = path {
                return NSWorkspace.shared.icon(forFile: p)
            }
            return nil
        }()

        // Idle tracking: carry forward from previous snapshot or start fresh
        let previousCPU = context.previousCPUTimes[identity] ?? 0
        let previousSeenAt = context.previousSeenTimes[identity]
        let currentCPU = cpuTimeUser + cpuTimeSystem
        let cpuChanged = currentCPU > previousCPU + 0.01
        let cpuPercent: Double = {
            guard let previousSeenAt else { return 0 }
            let elapsed = max(context.now.timeIntervalSince(previousSeenAt), 0.001)
            let cpuDelta = max(currentCPU - previousCPU, 0)
            return max((cpuDelta / elapsed) * 100, 0)
        }()

        let idleSince: Date? = {
            if cpuChanged { return nil }
            return context.previousIdleTimes[identity] ?? context.now
        }()

        return ATILProcess(
            identity: identity,
            pid: pid,
            ppid: ppid,
            uid: uid,
            gid: gid,
            name: name,
            executablePath: path,
            startTime: startTime,
            residentMemory: residentMemory,
            virtualMemory: virtualMemory,
            cpuTimeUser: cpuTimeUser,
            cpuTimeSystem: cpuTimeSystem,
            cpuPercent: cpuPercent,
            threadCount: threadCount,
            niceValue: niceValue,
            processState: processState,
            isOrphaned: isOrphaned,
            parentAlive: parentAlive,
            hasTTY: hasTTY,
            hasSockets: hasSockets,
            hasOwningApp: hasOwningApp,
            bundleIdentifier: bundleIdentifier,
            bundlePath: bundlePath,
            owningAppBundleIdentifier: owningAppBundleIdentifier,
            owningAppBundlePath: owningAppPath,
            category: .healthy, // placeholder, classifier sets this
            classificationReasons: [],
            lastSeen: context.now,
            idleSince: idleSince,
            launchdJob: launchdJob,
            appIcon: appIcon
        )
    }

    // MARK: - Full Scan

    func enumerateAll(context: EnumerationContext) -> [ATILProcess] {
        let pids = listAllPIDs()
        let appMap = buildRunningAppMap()
        let runningAppBundlePaths = buildRunningAppBundlePaths()
        return pids.compactMap {
            buildProcess(
                pid: $0,
                appMap: appMap,
                runningAppBundlePaths: runningAppBundlePaths,
                context: context
            )
        }
    }
}
