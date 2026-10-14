import ReplayKit
import SwiftUI
import UIKit

struct LiveBroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
        picker.preferredExtension = "com.custom.superagent.ai.broadcast"
        picker.showsMicrophoneButton = false
        picker.isAccessibilityElement = true
        picker.accessibilityLabel = "دەستپێکردن یان وەستاندنی شیکاریی لایڤی شاشە"
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
