import UIKit
import AVKit
import AVFoundation

class FloatingPiPController: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = FloatingPiPController()
    private var pipController: AVPictureInPictureController?
    private let coordsLabel = UILabel()
    private let summaryLabel = UILabel()
    
    func setupPiP(in sourceView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voiceChat, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        
        if #available(iOS 15.0, *) {
            let vc = AVPictureInPictureVideoCallViewController()
            vc.preferredContentSize = CGSize(width: 340, height: 150)
            vc.view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 0.96)
            
            coordsLabel.frame = CGRect(x: 10, y: 8, width: 320, height: 36)
            coordsLabel.textColor = .systemGreen
            coordsLabel.font = .monospacedSystemFont(ofSize: 21, weight: .heavy)
            coordsLabel.textAlignment = .center
            coordsLabel.text = "🎯 X: -- | Y: --"
            
            summaryLabel.frame = CGRect(x: 12, y: 46, width: 316, height: 95)
            summaryLabel.textColor = .white
            summaryLabel.font = .systemFont(ofSize: 13, weight: .medium)
            summaryLabel.numberOfLines = 4
            summaryLabel.textAlignment = .right
            summaryLabel.text = "SuperAgent لەسەر شاشە چالاکە. هەر سکرینشۆتێک بگریت خۆکارانە شیکار دەکرێت."
            
            vc.view.addSubview(coordsLabel)
            vc.view.addSubview(summaryLabel)
            
            let src = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: sourceView, contentViewController: vc)
            pipController = AVPictureInPictureController(contentSource: src)
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            pipController?.delegate = self
        }
    }
    
    func updateOverlay(coords: String, text: String) {
        DispatchQueue.main.async {
            self.coordsLabel.text = coords
            self.summaryLabel.text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        }
    }
    
    func togglePiP() {
        guard let pip = pipController else { return }
        pip.isPictureInPictureActive ? pip.stopPictureInPicture() : pip.startPictureInPicture()
    }
}

class VoiceEngine {
    static let shared = VoiceEngine()
    private let synth = AVSpeechSynthesizer()
    var enabled = true
    
    func speak(_ text: String) {
        guard enabled else { return }
        synth.stopSpeaking(at: .immediate)
        let clean = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        let utt = AVSpeechUtterance(string: String(clean.prefix(350)))
        utt.voice = AVSpeechSynthesisVoice(language: "ar-SA") ?? AVSpeechSynthesisVoice(language: "en-US")
        utt.rate = 0.52
        synth.speak(utt)
    }
}
