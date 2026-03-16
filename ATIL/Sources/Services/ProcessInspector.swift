import Darwin
import Foundation
import Security

enum InspectionSection: String, CaseIterable, Identifiable, Sendable {
    case openFiles
    case network
    case codeSignature
    case launchd
    case energy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openFiles: "Open Files"
        case .network: "Network"
        case .codeSignature: "Code Signature"
        case .launchd: "Launchd"
        case .energy: "Energy"
        }
    }
}

/// Detailed inspection data loaded lazily for the inspect panel.
struct ProcessInspectionData: Sendable {
    var openFiles: [OpenFileDescriptor]? = nil
    var listeningPorts: [ListeningPort]? = nil
    var establishedConnections: [EstablishedConnection]? = nil
    var unixDomainSockets: [UnixSocketInfo]? = nil
    var codeSignature: CodeSignatureInfo? = nil
    var launchdJob: LaunchdJobInfo? = nil
    var resourceUsage: ProcessResourceUsage? = nil

    mutating func merge(_ other: ProcessInspectionData) {
        if let openFiles = other.openFiles { self.openFiles = openFiles }
        if let listeningPorts = other.listeningPorts { self.listeningPorts = listeningPorts }
        if let establishedConnections = other.establishedConnections {
            self.establishedConnections = establishedConnections
        }
        if let unixDomainSockets = other.unixDomainSockets {
            self.unixDomainSockets = unixDomainSockets
        }
        if let codeSignature = other.codeSignature { self.codeSignature = codeSignature }
        if let launchdJob = other.launchdJob { self.launchdJob = launchdJob }
        if let resourceUsage = other.resourceUsage { self.resourceUsage = resourceUsage }
    }
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
    let family: String
}

struct EstablishedConnection: Identifiable, Sendable {
    let id = UUID()
    let family: String
    let localAddress: String
    let localPort: UInt16
    let remoteAddress: String
    let remotePort: UInt16
    let state: String
}

struct UnixSocketInfo: Identifiable, Sendable {
    let id = UUID()
    let fd: Int32
    let path: String
}

struct CodeSignatureInfo: Sendable {
    let isSigned: Bool
    let signingIdentity: String?
    let teamIdentifier: String?
    let isAppleSigned: Bool
    let isNotarized: Bool
    let codeIdentifier: String?
}

struct ProcessResourceUsage: Sendable {
    let idleWakeUps: UInt64
    let interruptWakeUps: UInt64
    let bytesRead: UInt64
    let bytesWritten: UInt64
}

/// Service that performs expensive per-process inspection on demand.
struct ProcessInspector: Sendable {
    private let codeSignatureReader = CodeSignatureReader()

    func load(
        section: InspectionSection,
        process: ATILProcess,
        launchdMap: [String: LaunchdJobInfo]
    ) -> ProcessInspectionData {
        switch section {
        case .openFiles:
            return ProcessInspectionData(openFiles: listOpenFiles(pid: process.pid))

        case .network:
            let network = inspectNetwork(pid: process.pid)
            return ProcessInspectionData(
                listeningPorts: network.listeningPorts,
                establishedConnections: network.establishedConnections,
                unixDomainSockets: network.unixSockets
            )

        case .codeSignature:
            return ProcessInspectionData(
                codeSignature: process.executablePath.flatMap { getCodeSignature(path: $0) }
            )

        case .launchd:
            return ProcessInspectionData(
                launchdJob: process.launchdJob ?? process.executablePath.flatMap { launchdMap[$0] }
            )

        case .energy:
            return ProcessInspectionData(resourceUsage: getResourceUsage(pid: process.pid))
        }
    }

    // MARK: - Open File Descriptors

    func listOpenFiles(pid: pid_t) -> [OpenFileDescriptor] {
        let fds = socketAndFileDescriptors(pid: pid)
        return fds.compactMap { fd -> OpenFileDescriptor? in
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

    // MARK: - Network

    func inspectNetwork(pid: pid_t) -> (
        listeningPorts: [ListeningPort],
        establishedConnections: [EstablishedConnection],
        unixSockets: [UnixSocketInfo]
    ) {
        let fds = socketAndFileDescriptors(pid: pid)
        var listeningPorts: [ListeningPort] = []
        var establishedConnections: [EstablishedConnection] = []
        var unixSockets: [UnixSocketInfo] = []

        for fd in fds where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
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

            let info = socketInfo.psi
            if info.soi_kind == SOCKINFO_TCP {
                let tcpInfo = info.soi_proto.pri_tcp
                let ports = tcpPorts(from: tcpInfo.tcpsi_ini)
                if info.soi_family == AF_INET || info.soi_family == AF_INET6 {
                    if tcpInfo.tcpsi_state == TSI_S_LISTEN {
                        listeningPorts.append(
                            ListeningPort(
                                port: ports.localPort,
                                family: socketFamilyName(info.soi_family)
                            )
                        )
                    } else if ports.remotePort > 0 {
                        establishedConnections.append(
                            EstablishedConnection(
                                family: socketFamilyName(info.soi_family),
                                localAddress: addressString(from: tcpInfo.tcpsi_ini, local: true),
                                localPort: ports.localPort,
                                remoteAddress: addressString(from: tcpInfo.tcpsi_ini, local: false),
                                remotePort: ports.remotePort,
                                state: tcpStateName(tcpInfo.tcpsi_state)
                            )
                        )
                    }
                }
            } else if info.soi_kind == SOCKINFO_UN {
                let pathSize = MemoryLayout.size(
                    ofValue: info.soi_proto.pri_un.unsi_addr.ua_sun.sun_path
                )
                let path = stringFromTuple(
                    info.soi_proto.pri_un.unsi_addr.ua_sun.sun_path,
                    maxLength: pathSize
                )
                unixSockets.append(
                    UnixSocketInfo(
                        fd: fd.proc_fd,
                        path: path.isEmpty ? "[anonymous]" : path
                    )
                )
            }
        }

        return (listeningPorts, establishedConnections, unixSockets)
    }

    // MARK: - Code Signature

    func getCodeSignature(path: String) -> CodeSignatureInfo? {
        codeSignatureReader.read(path: path)
    }

    // MARK: - Resource Usage

    func getResourceUsage(pid: pid_t) -> ProcessResourceUsage? {
        var usage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &usage) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard result == 0 else { return nil }

        return ProcessResourceUsage(
            idleWakeUps: usage.ri_pkg_idle_wkups,
            interruptWakeUps: usage.ri_interrupt_wkups,
            bytesRead: usage.ri_diskio_bytesread,
            bytesWritten: usage.ri_diskio_byteswritten
        )
    }

    // MARK: - Helpers

    private func socketAndFileDescriptors(pid: pid_t) -> [proc_fdinfo] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let fdInfoSize = Int32(MemoryLayout<proc_fdinfo>.size)
        let count = Int(bufferSize / fdInfoSize)
        guard count > 0 else { return [] }

        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize / fdInfoSize)
        return Array(fds.prefix(actualCount))
    }

    private func socketFamilyName(_ family: Int32) -> String {
        switch family {
        case AF_INET: "IPv4"
        case AF_INET6: "IPv6"
        case AF_UNIX: "Unix"
        default: "Other"
        }
    }

    private func tcpPorts(from info: in_sockinfo) -> (localPort: UInt16, remotePort: UInt16) {
        (
            UInt16(bigEndian: UInt16(truncatingIfNeeded: info.insi_lport)),
            UInt16(bigEndian: UInt16(truncatingIfNeeded: info.insi_fport))
        )
    }

    private func addressString(from info: in_sockinfo, local: Bool) -> String {
        if info.insi_vflag == INI_IPV4 {
            let address = local ? info.insi_laddr.ina_46.i46a_addr4 : info.insi_faddr.ina_46.i46a_addr4
            return ipv4String(address)
        }

        let address = local ? info.insi_laddr.ina_6 : info.insi_faddr.ina_6
        return ipv6String(address)
    }

    private func ipv4String(_ address: in_addr) -> String {
        var address = address
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(INET_ADDRSTRLEN))
        defer { buffer.deallocate() }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<in_addr>.size) {
                inet_ntop(AF_INET, $0, buffer, socklen_t(INET_ADDRSTRLEN))
            }.map { _ in
                String(cString: buffer)
            } ?? "0.0.0.0"
        }
    }

    private func ipv6String(_ address: in6_addr) -> String {
        var address = address
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(INET6_ADDRSTRLEN))
        defer { buffer.deallocate() }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<in6_addr>.size) {
                inet_ntop(AF_INET6, $0, buffer, socklen_t(INET6_ADDRSTRLEN))
            }.map { _ in
                String(cString: buffer)
            } ?? "::"
        }
    }

    private func tcpStateName(_ state: Int32) -> String {
        switch state {
        case TSI_S_CLOSED: "Closed"
        case TSI_S_LISTEN: "Listen"
        case TSI_S_SYN_SENT: "SYN Sent"
        case TSI_S_SYN_RECEIVED: "SYN Received"
        case TSI_S_ESTABLISHED: "Established"
        case TSI_S__CLOSE_WAIT: "Close Wait"
        case TSI_S_FIN_WAIT_1: "Fin Wait 1"
        case TSI_S_CLOSING: "Closing"
        case TSI_S_LAST_ACK: "Last Ack"
        case TSI_S_FIN_WAIT_2: "Fin Wait 2"
        case TSI_S_TIME_WAIT: "Time Wait"
        default: "Unknown"
        }
    }
}
