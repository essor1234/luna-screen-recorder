import Foundation
import AVFoundation
import CoreMedia

public final class VideoEncoder {
    private let outputURL: URL
    private let assetWriter: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private let encodingQueue = DispatchQueue(label: "com.screenrecorder.encoder")
    
    private var isSessionStarted = false
    private var isFinished = false
    
    private var isPaused = false
    private var pauseStartTime: CMTime?
    private var totalPausedDuration: CMTime = .zero
    
    public init(
        outputURL: URL,
        width: Int,
        height: Int,
        frameRate: Int = 30,
        enableSystemAudio: Bool = false,
        enableMicrophoneAudio: Bool = false
    ) throws {
        self.outputURL = outputURL
        
        // Ensure even dimensions for H.264
        let evenWidth = (width / 2) * 2
        let evenHeight = (height / 2) * 2
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }
        
        self.assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        // Optimize for web network streaming (places moov atom at beginning of file)
        self.assetWriter.shouldOptimizeForNetworkUse = true
        
        // Optimize bitrate for screen recording text sharpness and small file size (approx 2.5 Mbps)
        let targetBitrate = min(max(evenWidth * evenHeight * 2, 1_500_000), 3_500_000)
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: targetBitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate
            ]
        ]
        
        self.writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        self.writerInput.expectsMediaDataInRealTime = true
        
        guard assetWriter.canAdd(writerInput) else {
            throw NSError(domain: "VideoEncoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to asset writer"])
        }
        assetWriter.add(writerInput)
        
        if enableSystemAudio {
            let sysAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000
            ]
            let sInput = AVAssetWriterInput(mediaType: .audio, outputSettings: sysAudioSettings)
            sInput.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(sInput) {
                assetWriter.add(sInput)
                self.systemAudioInput = sInput
                print("[VideoEncoder] Configured System Audio AAC input track (48kHz stereo)")
            } else {
                print("[VideoEncoder] Warning: Cannot add system audio input to asset writer")
            }
        }
        
        if enableMicrophoneAudio {
            let micAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000
            ]
            let mInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
            mInput.expectsMediaDataInRealTime = true
            if assetWriter.canAdd(mInput) {
                assetWriter.add(mInput)
                self.micAudioInput = mInput
                print("[VideoEncoder] Configured Microphone AAC input track (44.1kHz mono)")
            } else {
                print("[VideoEncoder] Warning: Cannot add microphone audio input to asset writer")
            }
        }
    }
    
    public convenience init(outputURL: URL, width: Int, height: Int, frameRate: Int = 30, enableAudio: Bool = true) throws {
        try self.init(
            outputURL: outputURL,
            width: width,
            height: height,
            frameRate: frameRate,
            enableSystemAudio: false,
            enableMicrophoneAudio: enableAudio
        )
    }
    
    public func start() throws {
        guard assetWriter.startWriting() else {
            let err = assetWriter.error ?? NSError(domain: "VideoEncoder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to start writing"])
            print("[VideoEncoder] Failed to start writing: \(err)")
            throw err
        }
        print("[VideoEncoder] Started writing to \(outputURL.lastPathComponent)")
    }
    
    public func pause() {
        encodingQueue.async { [weak self] in
            guard let self = self, !self.isPaused else { return }
            self.isPaused = true
        }
    }
    
    public func resume() {
        encodingQueue.async { [weak self] in
            guard let self = self, self.isPaused else { return }
            self.isPaused = false
        }
    }
    
    public func append(sampleBuffer: CMSampleBuffer) {
        encodingQueue.async { [weak self] in
            guard let self = self, !self.isFinished else { return }
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            if self.isPaused {
                if self.pauseStartTime == nil {
                    self.pauseStartTime = pts
                }
                return
            }
            
            if let pauseStart = self.pauseStartTime {
                let currentPauseDuration = CMTimeSubtract(pts, pauseStart)
                self.totalPausedDuration = CMTimeAdd(self.totalPausedDuration, currentPauseDuration)
                self.pauseStartTime = nil
            }
            
            let adjustedPTS = CMTimeSubtract(pts, self.totalPausedDuration)
            
            if !self.isSessionStarted {
                self.assetWriter.startSession(atSourceTime: adjustedPTS)
                self.isSessionStarted = true
            }
            
            if self.totalPausedDuration.seconds > 0.001 {
                if let adjustedBuffer = self.adjustTimestamp(sampleBuffer: sampleBuffer, newPTS: adjustedPTS) {
                    if self.writerInput.isReadyForMoreMediaData {
                        self.writerInput.append(adjustedBuffer)
                    }
                }
            } else {
                if self.writerInput.isReadyForMoreMediaData {
                    self.writerInput.append(sampleBuffer)
                }
            }
        }
    }
    
    private func appendAudioSample(sampleBuffer: CMSampleBuffer, to targetInput: AVAssetWriterInput?) {
        encodingQueue.async { [weak self] in
            guard let self = self, !self.isFinished, let input = targetInput else { return }
            guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
            
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid else { return }
            
            if self.isPaused {
                return
            }
            
            let adjustedPTS = CMTimeSubtract(pts, self.totalPausedDuration)
            
            if !self.isSessionStarted {
                self.assetWriter.startSession(atSourceTime: adjustedPTS)
                self.isSessionStarted = true
            }
            
            if self.totalPausedDuration.seconds > 0.001 {
                if let adjustedBuffer = self.adjustTimestamp(sampleBuffer: sampleBuffer, newPTS: adjustedPTS) {
                    if input.isReadyForMoreMediaData {
                        input.append(adjustedBuffer)
                    }
                }
            } else {
                if input.isReadyForMoreMediaData {
                    input.append(sampleBuffer)
                }
            }
        }
    }
    
    public func appendSystemAudio(sampleBuffer: CMSampleBuffer) {
        appendAudioSample(sampleBuffer: sampleBuffer, to: systemAudioInput)
    }
    
    public func appendMicrophoneAudio(sampleBuffer: CMSampleBuffer) {
        appendAudioSample(sampleBuffer: sampleBuffer, to: micAudioInput)
    }
    
    public func appendAudio(sampleBuffer: CMSampleBuffer) {
        appendMicrophoneAudio(sampleBuffer: sampleBuffer)
    }
    
    private func adjustTimestamp(sampleBuffer: CMSampleBuffer, newPTS: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timingInfo = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &timingInfo, entriesNeededOut: &count)
        for i in 0..<count {
            timingInfo[i].presentationTimeStamp = newPTS
        }
        var newBuffer: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        return newBuffer
    }
    
    public func finish(completion: @escaping (Result<URL, Error>) -> Void) {
        encodingQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isFinished else { return }
            self.isFinished = true
            
            if !self.isSessionStarted {
                self.assetWriter.cancelWriting()
                completion(.failure(NSError(domain: "VideoEncoder", code: -3, userInfo: [NSLocalizedDescriptionKey: "No video frames were captured."])))
                return
            }
            
            self.systemAudioInput?.markAsFinished()
            self.micAudioInput?.markAsFinished()
            self.writerInput.markAsFinished()
            self.assetWriter.finishWriting {
                if let error = self.assetWriter.error {
                    completion(.failure(error))
                } else {
                    completion(.success(self.outputURL))
                }
            }
        }
    }
}
