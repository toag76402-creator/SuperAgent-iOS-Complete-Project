import Foundation
import Speech
import AVFoundation
import Combine

final class VoiceCommandManager: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = "گوێگرتنی دەنگ تەنها کاتێک ئەپ کراوەیە کاردەکات."

    var onCommand: ((String) -> Void)?
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: DispatchWorkItem?
    private var waitingForFinalResult = false
    private var lastTranscript = ""

    func startListening() {
        guard !isListening, !waitingForFinalResult else { return }
        transcript = ""
        lastTranscript = ""
        status = "داوای مۆڵەتی دەنگ دەکرێت..."
        SFSpeechRecognizer.requestAuthorization { [weak self] speechStatus in
            guard let self else { return }
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { self.status = "مۆڵەتی Speech Recognition پێویستە لە Settingsی iPhone چالاک بکرێت." }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard granted else {
                        self.status = "مۆڵەتی microphone پێنەدرا؛ هیچ گوێگرتنێک دەستپێنەکرا."
                        return
                    }
                    self.beginCapture()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        isListening = false
        waitingForFinalResult = true
        status = "گوێگرتن وەستا؛ چاوەڕێی تەواوبوونی transcript..."
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        timeout?.cancel()
        let finish = DispatchWorkItem { [weak self] in self?.finishWithTranscript() }
        timeout = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: finish)
    }

    func cancelListening() {
        timeout?.cancel()
        timeout = nil
        isListening = false
        waitingForFinalResult = false
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 { audioEngine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        status = "گوێگرتن هەڵوەشێنرایەوە؛ دەنگ نەگوازرایەوە."
        deactivateAudioSession()
    }

    private func beginCapture() {
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech Recognitionی iPhone بۆ زمان/ئەم کاتە بەردەست نییە."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest.shouldReportPartialResults = true
            request = recognitionRequest
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            waitingForFinalResult = false
            status = "گوێگرتن چالاکە؛ قسە بکە، پاشان دوگمەی وەستان دابگرە."
            task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async { self.transcript = text; self.lastTranscript = text }
                    if result.isFinal { DispatchQueue.main.async { self.finishWithTranscript() } }
                }
                if error != nil && self.waitingForFinalResult {
                    DispatchQueue.main.async { self.finishWithTranscript() }
                }
            }
            let limit = DispatchWorkItem { [weak self] in self?.stopListening() }
            timeout = limit
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: limit)
        } catch {
            cancelListening()
            status = "دەستپێکردنی microphone سەرکەوتوو نەبوو."
        }
    }

    private func finishWithTranscript() {
        guard waitingForFinalResult || isListening else { return }
        timeout?.cancel()
        timeout = nil
        isListening = false
        waitingForFinalResult = false
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 { audioEngine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        deactivateAudioSession()
        let command = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.isEmpty {
            status = "هیچ transcriptێک نەدۆزرایەوە."
        } else {
            status = "فەرمانی دەنگی ناردرا بۆ SuperAgent."
            onCommand?(command)
        }
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
