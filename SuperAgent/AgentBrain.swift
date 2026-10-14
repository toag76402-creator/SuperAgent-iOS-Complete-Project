import Foundation
import UIKit
import Photos
import Combine

final class AgentBrain: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var isThinking = false
    @Published var responseLog = "SuperAgent ئامادەیە؛ تەنها tool ـە ڕێگەپێدراوەکان بەکاردهێنێت."
    @Published var coordinatesDisplay = "🎯 X: -- | Y: --"
    @Published var currentImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var lastUserPrompt = ""
    @Published var liveBroadcasting = false
    @Published var liveStatus = "لایڤی شاشە ناچالاکە"
    @Published var pendingApproval: ToolApprovalRequest?

    let executionLog = AgentExecutionLog()
    private let approvalManager = ApprovalManager()
    private let toolExecutor = ToolExecutor()
    private var approvalSubscription: AnyCancellable?
    private var lastLiveFrameTimestamp: Double = 0
    private var lastLiveResponseTimestamp: Double = 0
    private var lastAutoAnalyzedScreenshotID: String?
    private var activeTurnID: UUID?
    private var activeTask: URLSessionDataTask?
    private var turnCancellation = AgentLoopCancellation()
    private var turnImage: UIImage?
    private var turnIsBOTB = false
    private var turnToolCalls = 0

    override init() {
        super.init()
        PHPhotoLibrary.shared().register(self)
        approvalSubscription = approvalManager.$pending
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.pendingApproval = $0 }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard AgentConfig.shared.autoAnalyzeScreenshots else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.analyzeLatestScreenshotIfNew()
        }
    }

    func grabLatestPhotoAndAnalyze(isBOTB: Bool) {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        guard let asset = PHAsset.fetchAssets(with: .image, options: opts).firstObject else {
            responseLog = "هیچ وێنەیەک لە Photos نەدۆزرایەوە."
            return
        }
        analyze(asset: asset, isBOTB: isBOTB)
    }

    private func analyzeLatestScreenshotIfNew() {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 20
        let assets = PHAsset.fetchAssets(with: .image, options: opts)
        guard let asset = (0..<assets.count).map({ assets.object(at: $0) }).first(where: {
            $0.mediaSubtypes.contains(.photoScreenshot)
        }), asset.localIdentifier != lastAutoAnalyzedScreenshotID else { return }
        lastAutoAnalyzedScreenshotID = asset.localIdentifier
        analyze(asset: asset, isBOTB: true)
    }

    private func analyze(asset: PHAsset, isBOTB: Bool) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImage(
            for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options
        ) { [weak self] image, _ in
            guard let self, let image else { return }
            DispatchQueue.main.async {
                self.currentImage = image
                self.executeAgent(
                    prompt: isBOTB ? "ئەم وێنەیە شیکار بکە. ئەگەر پۆتان دەدەیتەوە، دڵنیایی و نادڵنیایی ڕوون بکە و کۆئۆردینات بە نزیکەیی بڵێ." : "ئەم وێنەیە شیکار بکە.",
                    image: image,
                    isBOTBMode: isBOTB
                )
            }
        }
    }

    func syncLiveBroadcastState() {
        guard let shared = AgentConfig.sharedDefaults else { return }
        let active = shared.bool(forKey: "liveBroadcasting")
        liveBroadcasting = active
        if let status = shared.string(forKey: "liveResponse"), !status.isEmpty {
            liveStatus = active ? "لایڤ چالاکە؛ فریمە گۆڕاوەکان شیکار دەکرێن" : "لایڤ ناچالاکە"
            let updatedAt = shared.double(forKey: "liveUpdatedAt")
            if updatedAt > lastLiveResponseTimestamp {
                lastLiveResponseTimestamp = updatedAt
                responseLog = status
                let coordinates = shared.string(forKey: "liveCoordinates") ?? "🎯 X: -- | Y: --"
                coordinatesDisplay = coordinates
                if active { FloatingPiPController.shared.updateOverlay(coords: coordinates, text: status) }
            }
        }
        let frameTimestamp = shared.double(forKey: "liveFrameUpdatedAt")
        guard frameTimestamp > lastLiveFrameTimestamp,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AgentConfig.appGroupIdentifier),
              let data = try? Data(contentsOf: container.appendingPathComponent("live-latest-frame.jpg")),
              let image = UIImage(data: data) else { return }
        lastLiveFrameTimestamp = frameTimestamp
        currentImage = image
        processedImage = nil
    }

    func consumePendingIntentCommand() {
        guard let defaults = AgentConfig.sharedDefaults,
              let command = PendingCommandQueue.consume(from: defaults) else { return }
        executeAgent(prompt: command, image: currentImage, isBOTBMode: false)
    }

    func executeAgent(prompt: String, image: UIImage?, isBOTBMode: Bool) {
        activeTask?.cancel()
        turnCancellation.cancel()
        turnCancellation = AgentLoopCancellation()
        let id = UUID()
        activeTurnID = id
        approvalManager.resolve(approved: false)
        lastUserPrompt = prompt
        turnImage = image
        turnIsBOTB = isBOTBMode
        turnToolCalls = 0
        isThinking = true
        responseLog = "خەریکی وەڵامدانەوەم..."
        FloatingPiPController.shared.updateOverlay(coords: "⏳", text: "SuperAgent خەریکی کارە.")

        let config = AgentConfig.shared
        guard !APIRequestRouter.normalizedAPIKey(config.apiKey).isEmpty else {
            finishTurn(id, message: "کلیلی APIی خۆت لە Settings داخڵ بکە. کلیلی API لە کۆد/IPA دانەنراوە.")
            return
        }
        guard APIRequestRouter.resolve(apiKey: config.apiKey, endpoint: config.apiEndpoint, model: config.selectedModel) != nil else {
            finishTurn(id, message: "Endpoint یان ناوی مۆدێلی API دروست نییە؛ Settings بپشکنە.")
            return
        }
        runAgentStep(turnID: id, context: "", iteration: 0)
    }

    private func runAgentStep(turnID: UUID, context: String, iteration: Int) {
        guard activeTurnID == turnID, !turnCancellation.isCancelled else { return }
        guard iteration < AgentLoop.maximumIterations else {
            finishTurn(turnID, message: "Agent Loop گەیشتە سنووری \(AgentLoop.maximumIterations) هەنگاو؛ هیچ کردارێک زیاتر جێبەجێ نەکرا.")
            return
        }
        requestModel(turnID: turnID, context: context, retry: 0) { [weak self] response, errorMessage in
            guard let self, self.activeTurnID == turnID else { return }
            guard let response else {
                self.finishTurn(turnID, message: errorMessage ?? "وەڵامی پڕۆڤایدەر نەگەیشت.")
                return
            }
            switch AgentLoop.decision(from: response) {
            case .final(let text):
                let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? response : text
                self.finishTurn(turnID, message: finalText, speak: true)
            case .tool(let call):
                guard self.turnToolCalls < AgentLoop.maximumToolCallsPerTurn else {
                    self.finishTurn(turnID, message: "سنووری \(AgentLoop.maximumToolCallsPerTurn) tool call بۆ ئەم داواکارییە تەواو بوو؛ هیچ کردارێکی زیاتر جێبەجێ نەکرا.")
                    return
                }
                self.turnToolCalls += 1
                if let validation = ToolRegistry.validate(call, hasImage: self.turnImage != nil) {
                    self.executionLog.record(tool: call.name, succeeded: false)
                    let next = AgentLoop.appendToolResult(.failure(validation), toolName: call.name, to: context)
                    self.runAgentStep(turnID: turnID, context: next, iteration: iteration + 1)
                    return
                }
                self.executeTool(call, turnID: turnID, context: context, iteration: iteration)
            }
        }
    }

    private func executeTool(_ call: AgentToolCall, turnID: UUID, context: String, iteration: Int) {
        guard activeTurnID == turnID else { return }
        performTool(call, turnID: turnID, context: context, iteration: iteration, approved: false)
    }

    private func performTool(
        _ call: AgentToolCall,
        turnID: UUID,
        context: String,
        iteration: Int,
        approved: Bool
    ) {
        guard activeTurnID == turnID else { return }
        toolExecutor.execute(
            call,
            hasImage: turnImage != nil,
            isBroadcasting: liveBroadcasting,
            approved: approved
        ) { [weak self] result, approval in
            guard let self, self.activeTurnID == turnID else { return }
            if let approval {
                self.approvalManager.request(approval) { [weak self] accepted in
                    guard let self, self.activeTurnID == turnID else { return }
                    if accepted {
                        self.performTool(call, turnID: turnID, context: context, iteration: iteration, approved: true)
                    } else {
                        let denied = AgentToolResult.failure("بەکارهێنەر پەسەندی نەکرد؛ کردارەکە جێبەجێ نەکرا و نابێت دووبارە داوای پەسەندکردنی بۆ بکرێت.")
                        self.continueAfterTool(denied, name: call.name, turnID: turnID, context: context, iteration: iteration)
                    }
                }
                return
            }
            guard let result else { return }
            self.continueAfterTool(result, name: call.name, turnID: turnID, context: context, iteration: iteration)
        }
    }

    private func continueAfterTool(_ result: AgentToolResult, name: String, turnID: UUID, context: String, iteration: Int) {
        executionLog.record(tool: name, succeeded: result.succeeded)
        let next = AgentLoop.appendToolResult(result, toolName: name, to: context)
        runAgentStep(turnID: turnID, context: next, iteration: iteration + 1)
    }

    private func requestModel(
        turnID: UUID,
        context: String,
        retry: Int,
        completion: @escaping (String?, String?) -> Void
    ) {
        guard activeTurnID == turnID, !turnCancellation.isCancelled else { return }
        let config = AgentConfig.shared
        guard let route = APIRequestRouter.resolve(apiKey: config.apiKey, endpoint: config.apiEndpoint, model: config.selectedModel) else {
            completion(nil, "API configuration نادروستە.")
            return
        }
        let hasImage = turnImage != nil
        let system = config.coreSystemPrompt + "\n\n" + ToolRegistry.promptDescription(hasImage: hasImage)
        var userText = lastUserPrompt
        if let image = turnImage {
            userText += "\n\n[وێنەی هاوپێچکراو: قەبارە \(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale)) پیکسڵ.]"
        }
        if !context.isEmpty { userText += "\n\nئەنجامی ڕاستەقینەی tool ـەکانی ئەم turn ـە:\n\(context)\n\nبەپێی ئەم ئەنجامانە بەردەوام بە. دووبارە کردارێکی ڕەتکراوە مەکەوە." }
        var userContent: [[String: Any]] = [["type": "text", "text": userText]]
        if let image = turnImage {
            let source = turnIsBOTB ? drawCalibrationGrid(on: image) : image
            if let data = source.jpegData(compressionQuality: 0.78) {
                userContent.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())"]])
            }
        }
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": userContent]
        ]
        guard let payload = APIRequestRouter.makePayload(route: route, temperature: config.temperature, messages: messages),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil, "نەتوانرا داواکاریی API دروست بکرێت.")
            return
        }
        var request = URLRequest(url: route.url)
        request.timeoutInterval = AgentLoop.requestTimeout
        APIRequestRouter.configure(&request, route: route, body: body)
        activeTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.activeTurnID == turnID else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let error {
                    if retry < AgentLoop.maximumRetries {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(retry + 1) * 0.5) {
                            self.requestModel(turnID: turnID, context: context, retry: retry + 1, completion: completion)
                        }
                    } else {
                        completion(nil, "هەڵەی پەیوەندی بە \(route.safeEndpoint): \(error.localizedDescription)")
                    }
                    return
                }
                guard let data else { completion(nil, "وەڵامی API نەگەیشت. HTTP \(status). URL: \(route.safeEndpoint)"); return }
                guard (200...299).contains(status) else {
                    if status >= 500 && retry < AgentLoop.maximumRetries {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(retry + 1)) {
                            self.requestModel(turnID: turnID, context: context, retry: retry + 1, completion: completion)
                        }
                    } else {
                        completion(nil, APIRequestRouter.httpErrorMessage(statusCode: status, data: data, route: route))
                    }
                    return
                }
                guard let text = APIRequestRouter.responseText(from: data, provider: route.provider) else {
                    completion(nil, "شێوازی وەڵامی \(route.provider.displayName) چاوەڕوانکراو نییە.")
                    return
                }
                completion(text, nil)
            }
        }
        activeTask?.resume()
    }

    func respondToApproval(approved: Bool) {
        approvalManager.resolve(approved: approved)
    }

    func cancelCurrentTurn() {
        activeTask?.cancel()
        activeTask = nil
        turnCancellation.cancel()
        activeTurnID = nil
        isThinking = false
        approvalManager.resolve(approved: false)
        responseLog = "داواکاریی ئەجێنت هەڵوەشێنرایەوە."
    }

    func testAPIConnection(completion: @escaping (String) -> Void) {
        let config = AgentConfig.shared
        guard let route = APIRequestRouter.resolve(apiKey: config.apiKey, endpoint: config.apiEndpoint, model: config.selectedModel) else {
            completion("Endpoint، model، یان API key پشکنە.")
            return
        }
        let messages: [[String: Any]] = [["role": "user", "content": "Reply with only OK." ]]
        guard let payload = APIRequestRouter.makePayload(route: route, temperature: 0, messages: messages),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion("نەتوانرا داواکاریی تاقیکردنەوە دروست بکرێت.")
            return
        }
        var request = URLRequest(url: route.url)
        request.timeoutInterval = 30
        APIRequestRouter.configure(&request, route: route, body: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error { completion("هەڵەی پەیوەندی: \(error.localizedDescription)"); return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard let data else { completion("وەڵامی API نەگەیشت؛ HTTP \(status)."); return }
                guard (200...299).contains(status) else {
                    completion(APIRequestRouter.httpErrorMessage(statusCode: status, data: data, route: route))
                    return
                }
                guard APIRequestRouter.responseText(from: data, provider: route.provider) != nil else {
                    completion("API وەڵامی دا بەڵام شێوازی وەڵامەکە نەناسرا.")
                    return
                }
                completion("پەیوەندی بە \(route.provider.displayName) سەرکەوتوو بوو (HTTP \(status)).")
            }
        }.resume()
    }

    private func finishTurn(_ id: UUID, message: String, speak: Bool = false) {
        guard activeTurnID == id else { return }
        isThinking = false
        activeTask = nil
        responseLog = message
        if speak { VoiceEngine.shared.speak(message) }
        processCoordinates(from: message, originalImage: turnImage)
        FloatingPiPController.shared.updateOverlay(coords: coordinatesDisplay, text: message)
    }

    private func processCoordinates(from text: String, originalImage: UIImage?) {
        guard let start = text.range(of: "```json")?.upperBound,
              let end = text.range(of: "```", range: start..<text.endIndex)?.lowerBound else { return }
        let raw = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = raw.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let x = dictionary["targetX"] as? Int, let y = dictionary["targetY"] as? Int else { return }
        coordinatesDisplay = "🎯 X: \(x) | Y: \(y)"
        if let image = originalImage {
            let width = Int(image.size.width * image.scale)
            let height = Int(image.size.height * image.scale)
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let vectors = dictionary["vectors"] as? [[Int]] ?? []
            processedImage = drawVectorsAndCrosshair(on: image, targetX: x, targetY: y, vectors: vectors)
        }
    }

    private func drawCalibrationGrid(on image: UIImage) -> UIImage {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1.0)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let context = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return image }
        context.setStrokeColor(UIColor.cyan.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18), .foregroundColor: UIColor.yellow]
        for x in stride(from: CGFloat(0), to: width, by: 200) {
            context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: height)); context.strokePath()
            "\(Int(x))".draw(at: CGPoint(x: x + 3, y: 4), withAttributes: attributes)
        }
        for y in stride(from: CGFloat(0), to: height, by: 200) {
            context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: width, y: y)); context.strokePath()
            "\(Int(y))".draw(at: CGPoint(x: 4, y: y + 3), withAttributes: attributes)
        }
        let output = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return output ?? image
    }

    private func drawVectorsAndCrosshair(on image: UIImage, targetX: Int, targetY: Int, vectors: [[Int]]) -> UIImage {
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1.0)
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let context = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return image }
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(4)
        for vector in vectors where vector.count == 4 && vector.allSatisfy({ $0 >= 0 && $0 < max(Int(width), Int(height)) }) {
            context.move(to: CGPoint(x: vector[0], y: vector[1]))
            context.addLine(to: CGPoint(x: vector[2], y: vector[3]))
            context.strokePath()
        }
        let point = CGPoint(x: targetX, y: targetY)
        context.setStrokeColor(UIColor.red.cgColor)
        context.setLineWidth(5)
        context.strokeEllipse(in: CGRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48))
        context.move(to: CGPoint(x: point.x - 40, y: point.y)); context.addLine(to: CGPoint(x: point.x + 40, y: point.y))
        context.move(to: CGPoint(x: point.x, y: point.y - 40)); context.addLine(to: CGPoint(x: point.x, y: point.y + 40))
        context.strokePath()
        let output = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return output ?? image
    }
}
