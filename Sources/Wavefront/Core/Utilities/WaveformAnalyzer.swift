import AVFoundation
import Accelerate

/**
 * Analyzes audio files to generate waveform amplitude data.
 *
 * Uses AVFoundation to read audio samples and calculates RMS amplitude
 * values for visualization purposes.
 */
public final class WaveformAnalyzer {
    
    /// Shared singleton instance
    public static let shared = WaveformAnalyzer()
    
    /// Cache for analyzed waveforms keyed by track ID
    private var cache: [UUID: [CGFloat]] = [:]
    
    private init() {}
    
    /**
     * Analyzes an audio file and returns normalized amplitude values.
     *
     * @param url - URL to the audio file
     * @param sampleCount - Number of amplitude samples to generate
     * @returns Array of normalized amplitude values (0.0 to 1.0)
     */
    public func analyzeAudio(url: URL, sampleCount: Int = 200) async -> [CGFloat] {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            
            guard frameCount > 0 else {
                return generateFallbackWaveform(sampleCount: sampleCount)
            }
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                return generateFallbackWaveform(sampleCount: sampleCount)
            }
            
            try file.read(into: buffer)
            
            guard let floatChannelData = buffer.floatChannelData else {
                return generateFallbackWaveform(sampleCount: sampleCount)
            }
            
            let channelData = floatChannelData[0]
            let totalSamples = Int(buffer.frameLength)
            let samplesPerBar = totalSamples / sampleCount
            
            var amplitudes: [CGFloat] = []
            
            for i in 0..<sampleCount {
                let startSample = i * samplesPerBar
                let endSample = min(startSample + samplesPerBar, totalSamples)
                
                if startSample >= totalSamples {
                    amplitudes.append(0.0)
                    continue
                }
                
                // Calculate RMS for this segment
                var sum: Float = 0
                for j in startSample..<endSample {
                    let sample = channelData[j]
                    sum += sample * sample
                }
                
                let rms = sqrt(sum / Float(endSample - startSample))
                
                // Normalize and apply some scaling for better visualization
                let normalized = min(CGFloat(rms) * 3.0, 1.0)
                let scaled = 0.1 + (normalized * 0.9) // Minimum height of 10%
                amplitudes.append(scaled)
            }
            
            return amplitudes
            
        } catch {
            return generateFallbackWaveform(sampleCount: sampleCount)
        }
    }
    
    /**
     * Gets cached waveform or analyzes if not cached.
     *
     * @param track - The audio track to analyze
     * @param sampleCount - Number of samples to generate
     * @returns Array of normalized amplitude values
     */
    public func getWaveform(for trackId: UUID, url: URL, sampleCount: Int = 200) async -> [CGFloat] {
        if let cached = cache[trackId] {
            return cached
        }
        
        let waveform = await analyzeAudio(url: url, sampleCount: sampleCount)
        cache[trackId] = waveform
        return waveform
    }
    
    /**
     * Clears the waveform cache.
     */
    public func clearCache() {
        cache.removeAll()
    }
    
    /**
     * Generates a fallback waveform when audio analysis fails.
     * Uses a smooth sine-based pattern instead of random noise.
     */
    private func generateFallbackWaveform(sampleCount: Int) -> [CGFloat] {
        var bars: [CGFloat] = []
        for i in 0..<sampleCount {
            let phase = Double(i) / Double(sampleCount) * .pi * 8
            let base = 0.3 + 0.4 * abs(sin(phase))
            let variation = 0.1 * sin(phase * 3.7)
            bars.append(CGFloat(min(max(base + variation, 0.1), 1.0)))
        }
        return bars
    }
}
