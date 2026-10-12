import Foundation

@main
struct AudioDSPQAMain {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: audio-dsp-qa OUTPUT_DIRECTORY\n", stderr)
            exit(2)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var report: [[String: Any]] = []
        var pcmHashes = Set<String>()
        for effect in WitchSoundEffect.allCases {
            let wav = WitchAudioDSP.renderWAV(effect)
            guard wav.count > 44, String(data: wav.prefix(4), encoding: .ascii) == "RIFF",
                  String(data: wav[8..<12], encoding: .ascii) == "WAVE",
                  wav.count % 2 == 0 else { throw NSError(domain: "AudioDSPQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid WAV layout for \(effect.rawValue)"]) }
            let peak = WitchAudioDSP.measuredPeak(wav)
            guard peak > 0, peak <= WitchAudioDSP.peakLimit + 1.0 / Double(Int16.max) else {
                throw NSError(domain: "AudioDSPQA", code: 2, userInfo: [NSLocalizedDescriptionKey: "invalid peak \(peak) for \(effect.rawValue)"])
            }
            let pcm = wav.dropFirst(44)
            let hash = pcm.reduce(into: UInt64(14695981039346656037)) { value, byte in value = (value ^ UInt64(byte)) &* 1099511628211 }
            guard pcmHashes.insert(String(hash, radix: 16)).inserted else { throw NSError(domain: "AudioDSPQA", code: 3, userInfo: [NSLocalizedDescriptionKey: "duplicate waveform for \(effect.rawValue)"]) }
            let file = output.appendingPathComponent("sfx_\(effect.rawValue)_dsp_r001.wav")
            try wav.write(to: file, options: .atomic)
            report.append(["effect": effect.rawValue, "file": file.lastPathComponent, "bytes": wav.count,
                           "sampleRate": WitchAudioDSP.sampleRate, "channels": 1, "bitsPerSample": 16,
                           "durationSeconds": Double(wav.count - 44) / Double(WitchAudioDSP.sampleRate * 2), "peak": peak,
                           "source": "locally synthesized DSP candidate; no third-party recording"])
        }
        guard pcmHashes.count == WitchSoundEffect.allCases.count else { throw NSError(domain: "AudioDSPQA", code: 4) }
        let data = try JSONSerialization.data(withJSONObject: ["status": "PASS", "authority": "UNAPPROVED_TEST_OVERLAY", "effectCount": report.count, "effects": report], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("AUDIO_DSP_QA_R001.json"), options: .atomic)
        print("AUDIO_DSP_QA status=PASS effects=\(report.count) output=\(output.path)")
    }
}
