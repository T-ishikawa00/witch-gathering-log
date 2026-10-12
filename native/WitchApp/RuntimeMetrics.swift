import Foundation
import Darwin

@MainActor final class RuntimeMetrics {
    static let shared=RuntimeMetrics()
    private var durations:[Double]=[]
    private var sessionStart:Double?
    private var lastWrite=0.0
    private var totalFrames=0
    private var longFrames=0
    private var peakResident:UInt64=0
    func frame(delta:Double,time:Double,nodeCount:Int,context:String){
        guard ProcessInfo.processInfo.arguments.contains("--qa-isolated") else{return}
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
        if let d=try? JSONSerialization.data(withJSONObject:data,options:[.sortedKeys,.prettyPrinted]){let folder=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Witch03to05R1");try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try? d.write(to:folder.appendingPathComponent("runtime_metrics.json"),options:.atomic)}
    }
}
