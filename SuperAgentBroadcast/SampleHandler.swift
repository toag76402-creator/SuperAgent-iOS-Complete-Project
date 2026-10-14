import CoreImage
import CoreMedia
import CryptoKit
import Foundation
import ReplayKit
import UIKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let appGroup = "group.com.custom.superagent.ai"
    private let stateLock = NSLock()
    private let imageContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastSampleCheck = Date.distantPast
    private var lastFingerprint: Data?
    private var requestInFlight = false

    private var shared: UserDefaults? { UserDefaults(suiteName: appGroup) }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        shared?.set(true, forKey: "liveBroadcasting")
        shared?.set("🎯 X: -- | Y: --", forKey: "liveCoordinates")
        shared?.set("لایڤی شاشە چالاکە؛ شیکاریی وێنەکان هەر دوو چرکە جارێک ئەنجام دەدرێت.", forKey: "liveResponse")
        shared?.set(Date().timeIntervalSince1970, forKey: "liveUpdatedAt")
    }

    override func broadcastFinished() {
        shared?.set(false, forKey: "liveBroadcasting")
        shared?.set("لایڤی شاشە وەستێنرا.", forKey: "liveResponse")
        shared?.set(Date().timeIntervalSince1970, forKey: "liveUpdatedAt")
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            try? FileManager.default.removeItem(at: container.appendingPathComponent("live-latest-frame.jpg"))
        }
    }

    override func broadcastPaused() {
        shared?.set(false, forKey: "liveBroadcasting")
        shared?.set("لایڤ لە Control Center ـەوە پشووی داوە.", forKey: "liveResponse")
        shared?.set(Date().timeIntervalSince1970, forKey: "liveUpdatedAt")
    }

    override func broadcastResumed() {
        shared?.set(true, forKey: "liveBroadcasting")
        shared?.set("لایڤ دووبارە دەستی پێکرد.", forKey: "liveResponse")
        shared?.set(Date().timeIntervalSince1970, forKey: "liveUpdatedAt")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        let now = Date()
        stateLock.lock()
        guard !requestInFlight, now.timeIntervalSince(lastSampleCheck) >= 2.0 else {
            stateLock.unlock()
            return
        }
        lastSampleCheck = now
        stateLock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let frame = makeJPEG(from: pixelBuffer) else { return }
        let jpeg = frame.data
        let fingerprint = Data(SHA256.hash(data: jpeg))

        stateLock.lock()
        guard fingerprint != lastFingerprint else {
            stateLock.unlock()
            return
        }
        lastFingerprint = fingerprint
        requestInFlight = true
        stateLock.unlock()

        saveLatestFrame(jpeg)
        sendFrameToGemini(jpeg, width: frame.width, height: frame.height)
    }

    private func makeJPEG(from pixelBuffer: CVPixelBuffer) -> (data: Data, width: Int, height: Int)? {
        let original = CIImage(cvPixelBuffer: pixelBuffer)
        let width = original.extent.width
        guard width > 0 else { return nil }
        let scale = min(1.0, 1024.0 / width)
        let resized = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = imageContext.createCGImage(resized, from: resized.extent) else { return nil }
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.68) else { return nil }
        return (data, cgImage.width, cgImage.height)
    }

    private func saveLatestFrame(_ jpeg: Data) {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return }
        do {
            try jpeg.write(to: container.appendingPathComponent("live-latest-frame.jpg"), options: .atomic)
            shared?.set(Date().timeIntervalSince1970, forKey: "liveFrameUpdatedAt")
        } catch {
            shared?.set("نەتوانرا وێنەی لایڤ لەبیرگەی هاوبەشدا پاشەکەوت بکرێت.", forKey: "liveResponse")
        }
    }

    private func sendFrameToGemini(_ jpeg: Data, width: Int, height: Int) {
        guard let shared,
              let keyValue = shared.string(forKey: "apiKey") else {
            finishWithMessage("کلیلی Gemini لە Settings ـدا دانەنراوە.")
            return
        }
        let apiKey = normalizedAPIKey(keyValue)
        guard !apiKey.isEmpty else {
            finishWithMessage("کلیلی Gemini لە Settings ـدا دانەنراوە.")
            return
        }
        let endpoint = (shared.string(forKey: "apiEndpoint") ?? "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%60", with: "")
            .replacingOccurrences(of: "`", with: "")
        guard let url = URL(string: endpoint) else {
            finishWithMessage("URL ـی Gemini دروست نییە؛ Settings بپشکنە.")
            return
        }
        let model = shared.string(forKey: "selectedModel") ?? "gemini-3.8-flash"
        let base64 = jpeg.base64EncodedString()
        let followUp = shared.string(forKey: "liveCustomPrompt") ?? ""
        let prompt = "ئەمە فریمێکی نوێی شاشەی BOTB ـە، قەبارەی وێنە Width=\(width), Height=\(height) پیکسڵە. تەنها ئەو وردەکارییانە باس بکە کە لە وێنەکەدا بەڕاستی دیارن. گۆڕانکارییە نوێکان بە کورتی بڵێ. ئەگەر پۆتانی تۆپ لێکدەدەیتەوە، دڵنیایی و نادڵنیایی ڕوون بکە و کۆئۆردیناتی پیکسڵی تەنها بە نزیکەیی بدە؛ دڵنیایی ساختە مەدە. وەڵامێکی کورتی کوردی بنووسە و لە کۆتاییدا JSON ـی targetX و targetY دابنێ."
            + (followUp.isEmpty ? "" : "\nپرسیاری زیادەی بەکارهێنەر: \(followUp)")
        let messages: [[String: Any]] = [[
            "role": "user",
            "content": [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64)"]]
            ]
        ]]
        let body: [String: Any] = ["model": model, "temperature": 0.15, "messages": messages]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            finishWithMessage("نەتوانرا داواکاریی Gemini دروست بکرێت.")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.requestInFlight = false
                self.stateLock.unlock()
            }
            if let error {
                self.storeResponse("هەڵەی پەیوەندیی لایڤ: \(error.localizedDescription)")
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else {
                self.storeResponse("Gemini هیچ وەڵامێکی نەگەیاند. HTTP \(status)")
                return
            }
            guard (200...299).contains(status) else {
                let detail = self.providerErrorMessage(from: data, apiKey: apiKey)
                let hint = status == 401 || status == 403 ? "؛ کلیلی Gemini، جۆری API key، و Endpoint بپشکنە." : ""
                self.storeResponse("هەڵەی Gemini لە لایڤدا: HTTP \(status). \(detail)\(hint)")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                self.storeResponse("شێوازی وەڵامی لایڤی Gemini چاوەڕوانکراو نییە.")
                return
            }
            self.storeResponse(content)
            if let x = self.coordinate("targetX", in: content), let y = self.coordinate("targetY", in: content) {
                self.shared?.set("🎯 X: \(x) | Y: \(y)", forKey: "liveCoordinates")
            }
        }.resume()
    }

    private func coordinate(_ key: String, in text: String) -> Int? {
        let pattern = "\\\"\(key)\\\"\\s*:\\s*(-?\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }

    private func normalizedAPIKey(_ raw: String) -> String {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        key = key.replacingOccurrences(of: #"(?i)^Bearer\s+"#, with: "", options: .regularExpression)
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`“”‘’"))
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerErrorMessage(from data: Data, apiKey: String) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "وەڵامی API JSON نییە."
        }
        let error = json["error"] as? [String: Any]
        let message = (error?["message"] as? String)
            ?? (json["message"] as? String)
            ?? (error?["status"] as? String)
            ?? "وەڵامی پڕۆڤایدەر وردەکاریی زیاتر نادات."
        let safeMessage = message.replacingOccurrences(of: apiKey, with: "[hidden]")
        return String(safeMessage.prefix(240))
    }

    private func storeResponse(_ text: String) {
        shared?.set(text, forKey: "liveResponse")
        shared?.set(Date().timeIntervalSince1970, forKey: "liveUpdatedAt")
    }

    private func finishWithMessage(_ text: String) {
        storeResponse(text)
        stateLock.lock()
        requestInFlight = false
        stateLock.unlock()
    }
}
