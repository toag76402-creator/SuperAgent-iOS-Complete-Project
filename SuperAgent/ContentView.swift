import SwiftUI
import Combine

struct ContentView: View {
    @ObservedObject var brain: AgentBrain
    @ObservedObject var config: AgentConfig
    @StateObject private var voice = VoiceCommandManager()
    @State private var inputPrompt = ""
    @State private var isBOTBMode = false
    @State private var showSettings = false
    @State private var showImagePicker = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                HStack {
                    Text(brain.coordinatesDisplay)
                        .font(.system(.headline, design: .monospaced))
                        .foregroundColor(.green)
                        .padding(10)
                        .background(Color.black)
                        .cornerRadius(10)
                    Spacer()
                    Button(action: { FloatingPiPController.shared.togglePiP() }) {
                        Label("PiP", systemImage: "pip.enter")
                            .font(.caption.bold())
                            .padding(10)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(config.customMacros) { macro in
                            Button {
                                brain.executeAgent(prompt: macro.promptCommand, image: brain.currentImage, isBOTBMode: isBOTBMode)
                            } label: {
                                Text(macro.title)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.25))
                                    .foregroundColor(.cyan)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)).frame(height: 190)
                    if let image = brain.processedImage ?? brain.currentImage {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 190).cornerRadius(12)
                    } else {
                        Text("وێنە هەڵبژێرە یان بە ڕەزامەندی خۆت screen broadcast دەستپێبکە.")
                            .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding()
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    Button { brain.grabLatestPhotoAndAnalyze(isBOTB: isBOTBMode) } label: {
                        Label("دوایین وێنە", systemImage: "viewfinder")
                            .font(.caption.bold()).frame(maxWidth: .infinity).padding(10)
                            .background(Color.blue).foregroundColor(.white).cornerRadius(10)
                    }
                    Button { showImagePicker = true } label: {
                        Label("هەڵبژاردنی وێنە", systemImage: "photo")
                            .font(.caption.bold()).frame(maxWidth: .infinity).padding(10)
                            .background(Color.orange).foregroundColor(.white).cornerRadius(10)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 6) {
                    HStack {
                        Button {
                            if voice.isListening { voice.stopListening() } else { voice.startListening() }
                        } label: {
                            Label(voice.isListening ? "وەستانی گوێگرتن" : "فەرمانی دەنگی", systemImage: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding(11)
                                .background(voice.isListening ? Color.red : Color.green)
                                .foregroundColor(.white).cornerRadius(12)
                        }
                        .accessibilityHint("گوێگرتن تەنها دوای داگرتنی دوگمە و بە مۆڵەتی microphone دەستپێدەکات.")
                        if voice.isListening {
                            Button("هەڵوەشاندنەوە") { voice.cancelListening() }
                                .font(.caption).foregroundColor(.red)
                        }
                    }
                    Text(voice.transcript.isEmpty ? voice.status : voice.transcript)
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    Toggle("BOTB", isOn: $isBOTBMode).labelsHidden()
                    Text("BOTB").font(.caption.bold())
                    LiveBroadcastPicker().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(brain.liveBroadcasting ? "لایڤ چالاکە" : "لایڤی شاشە")
                            .font(.caption.bold())
                        Text("تەنها بە دەستپێکردن لە Control Center")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal)

                ScrollView {
                    Text(brain.isThinking ? "⏳ خەریکی کارە..." : brain.responseLog)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                        .padding()
                }
                .background(Color.secondary.opacity(0.1)).cornerRadius(12).padding(.horizontal)

                HStack(spacing: 10) {
                    TextField("فەرمان یان پرسیار بنووسە...", text: $inputPrompt)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.sentences)
                    Button {
                        let text = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        brain.executeAgent(prompt: text, image: brain.currentImage, isBOTBMode: isBOTBMode)
                        inputPrompt = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundColor(.green)
                    }
                    .disabled(inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || brain.isThinking)
                    if brain.isThinking {
                        Button { brain.cancelCurrentTurn() } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal).padding(.bottom, 6)
            }
            .navigationTitle("SuperAgent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $showSettings) { ControlCenterSettingsView(config: config, brain: brain) }
            .sheet(isPresented: $showImagePicker) {
                PhotoLibraryPicker { image in
                    showImagePicker = false
                    brain.currentImage = image
                    brain.processedImage = nil
                    brain.executeAgent(prompt: "ئەم وێنەیە شیکار بکە و تەنها ئەو زانیارییانە باس بکە کە لە وێنەکەدا دیارن.", image: image, isBOTBMode: isBOTBMode)
                }
            }
            .background(PiPInitializerView())
            .onAppear {
                voice.onCommand = { command in
                    brain.executeAgent(prompt: command, image: brain.currentImage, isBOTBMode: false)
                }
            }
            .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
                brain.syncLiveBroadcastState()
                brain.consumePendingIntentCommand()
            }
            .onChange(of: scenePhase) { phase in
                if phase != .active { voice.cancelListening() }
            }
            .alert(item: $brain.pendingApproval) { request in
                Alert(
                    title: Text("SuperAgent داوای پەسەندکردن دەکات"),
                    message: Text("\(request.title)\n\n\(request.details)"),
                    primaryButton: .default(Text("پەسەند دەکەم"), action: { brain.respondToApproval(approved: true) }),
                    secondaryButton: .cancel(Text("ڕەت دەکەم"), action: { brain.respondToApproval(approved: false) })
                )
            }
        }
    }
}

struct ControlCenterSettingsView: View {
    @ObservedObject var config: AgentConfig
    @ObservedObject var brain: AgentBrain
    @State private var apiTestStatus = ""
    @State private var newMacroTitle = ""
    @State private var newMacroPrompt = ""
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API / Ollama Cloud")) {
                    TextField("API Endpoint", text: $config.apiEndpoint)
                        .font(.caption).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(config.detectedProvider != .custom)
                    SecureField("API Key (خۆت دایبنێ)", text: $config.apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $config.selectedModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("بنەڕەت: https://ollama.com/v1/chat/completions — gemma4:31b. API key لە IPA دانەنراوە؛ کلیلەکەت تەنها لە ئامێری خۆت داخڵ بکە.")
                        .font(.caption2).foregroundColor(.secondary)
                    Button("تاقیکردنەوەی API") {
                        config.normalizeAPISettings()
                        apiTestStatus = "تاقیکردنەوە دەکرێت..."
                        brain.testAPIConnection { apiTestStatus = $0 }
                    }
                    if !apiTestStatus.isEmpty { Text(apiTestStatus).font(.caption).textSelection(.enabled) }
                    VStack(alignment: .leading) {
                        Text("Temperature: \(String(format: "%.2f", config.temperature))")
                        Slider(value: $config.temperature, in: 0...1.5, step: 0.05)
                    }
                }

                Section(header: Text("دەنگ و ڕەزامەندی")) {
                    Text("Microphone تەنها کاتێک بە دوگمە دەستپێدەکەیت و ئەپەکە لە پێشەوەیە چالاک دەبێت. لە background گوێناگرێت؛ بە گۆڕینی scene بۆ background هەڵدەوەشێتەوە.")
                        .font(.caption)
                    Text("کردنەوەی URL، کۆپیکردن بۆ clipboard و دروستکردنی بیرخستنەوە هەمیشە پەسەندکردنی تۆیان دەوێت. Webhook و server API لەم وەشانەدا ڕێک نەخراون.")
                        .font(.caption)
                    Toggle("شیکاریی خۆکار لە کاتی سکرینشۆت", isOn: $config.autoAnalyzeScreenshots)
                }

                Section(header: Text("ڕێنمایی کەسیی مۆدێل")) {
                    TextEditor(text: $config.coreSystemPrompt).frame(height: 130)
                    Text("Tool ـەکان و کردارە ڕێگەپێدراوەکان بە کۆد دیاری دەکرێن؛ ئەم دەقە ناتوانێت سنووری iOS یان پەسەندکردن لاببات.")
                        .font(.caption2).foregroundColor(.secondary)
                }

                Section(header: Text("تۆماری کردارەکان (بێ نهێنی و بێ ناوەڕۆکی پاراستراو)")) {
                    if brain.executionLog.entries.isEmpty {
                        Text("هێشتا هیچ toolێک بەڕێوە نەچووە.").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(Array(brain.executionLog.entries.enumerated()), id: \.offset) { _, entry in
                            Text(entry).font(.caption)
                        }
                    }
                }

                Section(header: Text("فەرمانی خێرا")) {
                    ForEach(config.customMacros) { macro in
                        Text("\(macro.title): \(macro.promptCommand)").font(.caption)
                    }
                    TextField("ناوی فەرمان", text: $newMacroTitle)
                    TextField("دەقی فەرمان", text: $newMacroPrompt)
                    Button("زیادکردنی فەرمان") {
                        let title = newMacroTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let prompt = newMacroPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, !prompt.isEmpty, title.count <= 50, prompt.count <= 500 else { return }
                        config.customMacros.append(CustomMacro(title: title, promptCommand: prompt))
                        newMacroTitle = ""
                        newMacroPrompt = ""
                    }
                }

                Section {
                    Text("App Intents و Shortcuts لە iOS 16+ زیادکراون. Hey Siri, ask SuperAgent ... فەرمانەکە دەخاتە نۆرە و ئەپەکە دەکاتەوە؛ هەر tool ـێکی هەستیار پێش جێبەجێکردن approval دەوێت.")
                        .font(.caption)
                }
            }
            .navigationTitle("ڕێکخستن")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("داخستن") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

struct PiPInitializerView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        DispatchQueue.main.async { FloatingPiPController.shared.setupPiP(in: view) }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
