import Foundation
import Darwin

/// Selects the existing ordinary-QA metrics folder or a validated R259-only
/// child folder. Malformed R259 invocations fail closed instead of falling
/// through to the shared namespace.
enum RuntimeMetricsOutputDirectoryR269 {
    static func resolve(arguments: [String], applicationSupport: URL) -> URL? {
        let isolatedArgs = arguments.filter { $0 == "--qa-isolated" }
        guard isolatedArgs.count == 1 else { return nil }

        let sequenceArgs = arguments.filter { $0.hasPrefix("--qa-jelly-sequence-r259") }
        let meshArgs = arguments.filter { $0.hasPrefix("--qa-jelly-mesh-r254") }
        let profileArgs = arguments.filter { $0.hasPrefix("--qa-jelly-profile=") }
        let isR259Request = !sequenceArgs.isEmpty || !meshArgs.isEmpty || !profileArgs.isEmpty
        let common = applicationSupport.appendingPathComponent("Witch03to05R1", isDirectory: true)
        guard isR259Request else { return common }

        // R259 must not be mixed with earlier motion/mesh QA modes; otherwise
        // the shared metrics writer could observe a different run contract.
        let conflictingLegacyArgs = arguments.filter {
            $0.hasPrefix("--qa-jelly-mesh-r135") || $0.hasPrefix("--qa-jelly-sequence-r137")
        }

        let keyArgs = arguments.filter { $0.hasPrefix("--qa-save-key=") }
        let actorArgs = arguments.filter { $0.hasPrefix("--art-audit=") }
        guard sequenceArgs == ["--qa-jelly-sequence-r259"],
              meshArgs == ["--qa-jelly-mesh-r254"],
              profileArgs.count == 1,
              let profile = profileArgs.first?.split(separator: "=", maxSplits: 1).last.map(String.init),
              profile == "quadrature" || profile == "traveling_wave",
              conflictingLegacyArgs.isEmpty,
              keyArgs.count == 1,
              let rawKey = keyArgs.first?.split(separator: "=", maxSplits: 1).last.map(String.init),
              let uuid = UUID(uuidString: rawKey), uuid.uuidString.lowercased() == rawKey.lowercased(),
              actorArgs == ["--art-audit=ACT_E_R02_03"] else {
            return nil
        }
        return common.appendingPathComponent("R259-" + rawKey, isDirectory: true)
    }
}

@MainActor final class RuntimeMetrics {
    static let shared=RuntimeMetrics()
    private var durations:[Double]=[]
    private var sessionStart:Double?
    private var lastWrite=0.0
    private var totalFrames=0
    private var longFrames=0
    private var peakResident:UInt64=0
    func frame(delta:Double,time:Double,nodeCount:Int,context:String){
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-isolated") else{return}
        if sessionStart==nil{sessionStart=time}
        guard time-(sessionStart ?? time)>2 else{return}
        totalFrames+=1;if delta>0.05{longFrames+=1}
        durations.append(delta);if durations.count>3600{durations.removeFirst()}
        guard time-lastWrite>3 else{return};lastWrite=time
        var info=mach_task_basic_info();var count=mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let status=withUnsafeMutablePointer(to:&info){ptr in ptr.withMemoryRebound(to:integer_t.self,capacity:Int(count)){task_info(mach_task_self_,task_flavor_t(MACH_TASK_BASIC_INFO),$0,&count)}}
        let resident=status==KERN_SUCCESS ? info.resident_size:0;peakResident=max(peakResident,resident)
        let ordered=durations.sorted();let p95=ordered.isEmpty ? 0:ordered[min(ordered.count-1,Int(Double(ordered.count)*0.95))]
        let mean=durations.reduce(0,+)/Double(max(1,durations.count))
        let data:[String:Any]=["scope":"SIMULATOR_QA_ONLY_NOT_PHYSICAL_DEVICE","measuredSeconds":time-(sessionStart ?? time)-2,"frames":totalFrames,"windowFrames":durations.count,"meanFPS":mean>0 ? 1/mean:0,"p95FrameSeconds":p95,"framesOver50ms":longFrames,"residentBytes":resident,"observedPeakResidentBytes":peakResident,"nodeCount":nodeCount,"scene":context,"date":ISO8601DateFormatter().string(from:Date())]
        guard let folder = RuntimeMetricsOutputDirectoryR269.resolve(
            arguments: arguments,
            applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        ) else { return }
        if let d=try? JSONSerialization.data(withJSONObject:data,options:[.sortedKeys,.prettyPrinted]){
            try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try? d.write(to:folder.appendingPathComponent("runtime_metrics.json"),options:.atomic)
        }
    }
}
