import AVFoundation
import UIKit

protocol ImageCaptureDelegate {
    func captureOutput(ciimage: CIImage)
}

fileprivate struct Const {
    static let fps: Int32 = 15
}

class ImageCapture: NSObject {
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput",
                                                     qos: .userInitiated,
                                                     attributes: [],
                                                     autoreleaseFrequency: .workItem)
    private(set) var session = AVCaptureSession()
    // キャプチャー画像サイズ
    private(set) var videoWidth = 0
    private(set) var videoHeight = 0
    // キャプチャー画像の通知用デリゲート
    var delegate: ImageCaptureDelegate?
    
    override init() {
        super.init()
        
        setupAVCapture()
    }
    
    private func setupAVCapture() {
        let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                           mediaType: .video,
                                                           position: .back).devices.first
        guard let deviceInput = try? AVCaptureDeviceInput(device: videoDevice!) else { return }
        // capture セッション セットアップ
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        
        // 入力デバイス指定
        session.addInput(deviceInput)
        
        // 出力先の設定
        session.addOutput(videoDataOutput)
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        let captureConnection = videoDataOutput.connection(with: .video)
        captureConnection?.isEnabled = true
        
        try? videoDevice!.lockForConfiguration()
        // ビデオの画像サイズ取得
        let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice?.activeFormat.formatDescription)!)
        videoWidth = Int(dimensions.width)
        videoHeight = Int(dimensions.height)
        
        // FPSを設定
        videoDevice!.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Const.fps)
        videoDevice!.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Const.fps)
        
        videoDevice!.unlockForConfiguration()
        
        session.commitConfiguration()
    }
}

extension ImageCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciimage = CIImage(cvPixelBuffer: pb)
        delegate?.captureOutput(ciimage: ciimage)
    }
}
