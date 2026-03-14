import Darwin
import Foundation
import Security

/// Detailed inspection data loaded lazily for the inspect panel.
struct ProcessInspectionData: Sendable {
    let openFiles: [OpenFileDescriptor]
    let listeningPorts: [ListeningPort]
    let codeSignature: CodeSignatureInfo?
    let launchdJob: LaunchdJobInfo?
}

struct OpenFileDescriptor: Identifiable, Sendable {
    let id = UUID()
    let fd: Int32
    let path: String
    let type: FDType

    enum FDType: String, Sendable {
        case file
        case socket
        case pipe
        case other
    }
}

struct ListeningPort: Identifiable, Sendable {
    let id = UUID()
    let port: UInt16
    let family: String // "IPv4" / "IPv6"
}

struct CodeSignatureInfo: Sendable {
    let isSigned: Bool
    let signingIdentity: String?
    let teamIdentifier: String?
    let isAppleSigned: Bool
    let isNotarized: Bool
}

/// Service that performs expensive per-process inspection on demand.
struct ProcessInspector: Sendable {

    // MARK: - Open File Descriptors

    func listOpenFiles(pid: pid_t) -> [OpenFileDescriptor] {
        // Get the buffer size needed
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let fdInfoSize = Int32(MemoryLayout<proc_fdinfo>.size)
        let count = bufferSize / fdInfoSize

        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(count))
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize / fdInfoSize)

        return fds.prefix(actualCount).compactMap { fd -> OpenFileDescriptor? in
            let fdType: OpenFileDescriptor.FDType
            switch fd.proc_fdtype {
            case UInt32(PROX_FDTYPE_VNODE): fdType = .file
            case UInt32(PROX_FDTYPE_SOCKET): fdType = .socket
            case UInt32(PROX_FDTYPE_PIPE): fdType = .pipe
            default: fdType = .other
            }

            var path = ""
            if fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
                var vnodeInfo = vnode_fdinfowithpath()
                let vnodeSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                let result = proc_pidfdinfo(
                    pid,
                    fd.proc_fd,
                    PROC_PIDFDVNODEPATHINFO,
                    &vnodeInfo,
                    vnodeSize
                )
                if result > 0 {
                    path = stringFromTuple(vnodeInfo.pvip.vip_path, maxLength: Int(MAXPATHLEN))
                }
            }

            return OpenFileDescriptor(
                fd: fd.proc_fd,
                path: path.isEmpty ? "[\(fdType.rawValue)]" : path,
                type: fdType
            )
        }
    }

    // MARK: - Listening Ports

    func listListeningPorts(pid: pid_t) -> [ListeningPort] {
        // Get FDs, filter to sockets, check if listening
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let fdInfoSize = Int32(MemoryLayout<proc_fdinfo>.size)
        let count = bufferSize / fdInfoSize
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(count))
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize / fdInfoSize)
        var ports: [ListeningPort] = []

        for fd in fds.prefix(actualCount) {
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }

            var socketInfo = socket_fdinfo()
            let socketSize = Int32(MemoryLayout<socket_fdinfo>.size)
            let result = proc_pidfdinfo(
                pid,
                fd.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &socketInfo,
                socketSize
            )
            guard result > 0 else { continue }

            let si = socketInfo.psi
            // Check if TCP and listening (state 1 = LISTEN)
            guard si.soi_kind == SOCKINFO_TCP else { continue }
            guard si.soi_proto.pri_tcp.tcpsi_state == 1 else { continue } // TSI_S_LISTEN

            let family: String
            let port: UInt16
            if si.soi_family == AF_INET {
                family = "IPv4"
                port = UInt16(bigEndian: UInt16(truncatingIfNeeded: si.soi_proto.pri_tcp.tcpsi_ini.insi_lport))
            } else if si.soi_family == AF_INET6 {
                family = "IPv6"
                port = UInt16(bigEndian: UInt16(truncatingIfNeeded: si.soi_proto.pri_tcp.tcpsi_ini.insi_lport))
            } else {
                continue
            }

            if port > 0 {
                ports.append(ListeningPort(port: port, family: family))
            }
        }

        return ports
    }

    // MARK: - Code Signature

    func getCodeSignature(path: String) -> CodeSignatureInfo? {
        let url = URL(fileURLWithPath: path)
        var staticCode: SecStaticCode?

        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let code = staticCode
        else {
            return CodeSignatureInfo(
                isSigned: false,
                signingIdentity: nil,
                teamIdentifier: nil,
                isAppleSigned: false,
                isNotarized: false
            )
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else {
            return CodeSignatureInfo(
                isSigned: true,
                signingIdentity: nil,
                teamIdentifier: nil,
                isAppleSigned: false,
                isNotarized: false
            )
        }

        let identity = dict[kSecCodeInfoIdentifier as String] as? String
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String

        // Check for Apple-signed
        let isApple = identity?.hasPrefix("com.apple.") ?? false

        // Notarization: check if the code has been validated
        let isNotarized = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            nil
        ) == errSecSuccess

        return CodeSignatureInfo(
            isSigned: true,
            signingIdentity: identity,
            teamIdentifier: teamID,
            isAppleSigned: isApple,
            isNotarized: isNotarized
        )
    }

    // MARK: - Full Inspection

    func inspect(process: ATILProcess, launchdMap: [String: LaunchdJobInfo]) -> ProcessInspectionData {
        let openFiles = listOpenFiles(pid: process.pid)
        let listeningPorts = listListeningPorts(pid: process.pid)
        let codeSignature = process.executablePath.flatMap { getCodeSignature(path: $0) }
        let launchdJob = process.executablePath.flatMap { launchdMap[$0] }

        return ProcessInspectionData(
            openFiles: openFiles,
            listeningPorts: listeningPorts,
            codeSignature: codeSignature,
            launchdJob: launchdJob
        )
    }
}
