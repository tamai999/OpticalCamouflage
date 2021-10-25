import UIKit
import simd
import Vision
import Accelerate

fileprivate struct Const {
    static let imageSize = 513
    //    static let objectLabel = 5    // bottle
    static let objectLabel = 15    // person
    
    static let heightFieldRadius = 100
    static let shaderMaterialScale = 200
    
    static let morphologyClosingRadius: Float = 5
    static let morphologyOpeningRadius: Float = 10
}

class ViewController: UIViewController {
    
    @IBOutlet weak var topImageView: UIImageView!
    @IBOutlet weak var bottomImageView: UIImageView!
    
    private let ciContext = CIContext(options: [
        .cacheIntermediates : false
    ])
    
    private lazy var imageCapture = ImageCapture()
    
    // フィルター
    private var medianImageFilter = MedianImageFilter()
    private let morphologyErodeFilter = CIFilter.morphologyMinimum()
    private let morphologyDilateFilter = CIFilter.morphologyMaximum()
    private let heightFieldFilter = CIFilter.heightFieldFromMask()
    private let shaderMaterialFilter = CIFilter.shadedMaterial()
    private let multiplyCompositingFilter = CIFilter.multiplyCompositing()
    private var compositeFilter = CompositeFilter()
    
    // メディアン画像用バッファ
    private var median1stStepImageList: [CGImage] = []
    private var median2ndStepImageList: [CGImage] = []
    private var median3rdStepImageList: [CGImage] = []
    // メディアン画像
    private var medianImage: CGImage?
    // 光学迷彩画像
    private var opticalCamouflageImage: CGImage?
    // Vision Model
    private var visionRequest: VNCoreMLRequest?
    private var inVisionProcess = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupVision()
        
        // キャプチャ開始
        imageCapture.delegate = self
        imageCapture.session.startRunning()
    }
}

extension ViewController: ImageCaptureDelegate {
    
    func captureOutput(ciimage: CIImage) {
        // 右回転して向きを縦に直す
        let rotatedImage = ciimage.oriented(.right)
        guard let croppedImage = rotatedImage.crop(frame: CGRect(x: Int(rotatedImage.extent.size.width) / 2 - Const.imageSize / 2,
                                                                 y: Int(rotatedImage.extent.size.height) / 2 - Const.imageSize / 2,
                                                                 width: Const.imageSize,
                                                                 height: Const.imageSize)) else {
            return
        }
        // 入力画像を生成
        guard let videoImage = ciContext.createCGImage(croppedImage, from: croppedImage.extent) else { return }
        // 画像間の中央値で画像を生成
        DispatchQueue.global(qos: .userInteractive).async {
            if let median = self.createMedianImage(cgImage: videoImage) {
                self.medianImage = median
            }
        }
        // セマンティック・セグメンテーション
        if !inVisionProcess {
            inVisionProcess = true
            
            DispatchQueue.global(qos: .userInteractive).async {
                let handler = VNImageRequestHandler(ciImage: CIImage(cgImage: videoImage), options: [:])
                try? handler.perform([self.visionRequest!])
                self.inVisionProcess = false
            }
        }
        
        DispatchQueue.main.async {
            // 入力画像出力
            self.bottomImageView.image = UIImage(cgImage: videoImage)
            // 光学迷彩画像出力
            if let image = self.opticalCamouflageImage {
                self.topImageView.image = UIImage(cgImage: image)
            }
        }
    }
}

private extension ViewController {
    
    private func setupVision() {
        
        guard let visionModel = try? VNCoreMLModel(for: DeepLabV3(configuration: MLModelConfiguration()).model) else { return }
        let request = VNCoreMLRequest(model: visionModel) { request, error in
            guard let observations = request.results as? [VNCoreMLFeatureValueObservation],
                  let segmentationMap = observations.first?.featureValue.multiArrayValue else { return }
            
            // 物体のマスク画像生成
            guard let maskImage = self.createMaskImage(segmentedMap: segmentationMap) else { return }
            // マスク画像と中央値画像から光学迷彩画像を生成
            guard let median = self.medianImage else { return }
            self.opticalCamouflageImage = self.createOpticalCamouflageImage(mask: maskImage, median: median)
        }
        
        request.imageCropAndScaleOption = .centerCrop
        visionRequest = request
    }
    
    /// 画像間の中央値で画像を作る
    func createMedianImage(cgImage: CGImage) -> CGImage? {
        median1stStepImageList.append(cgImage)
        // １段階目メディアン画像生成
        medianImageFilter.inputList = median1stStepImageList.map { CIImage(cgImage: $0) }
        guard let output = medianImageFilter.outputImage else { return nil }
        
        // ２段階目のメディアンフィルタ用画像蓄積
        median2ndStepImageList.append(ciContext.createCGImage(output, from: output.extent)!)
        median1stStepImageList.removeAll()
        // ２段階目メディアン画像生成
        medianImageFilter.inputList = median2ndStepImageList.map { CIImage(cgImage: $0) }
        guard let output = medianImageFilter.outputImage else { return nil }
        
        // ３段階目のメディアンフィルタ用画像蓄積
        median3rdStepImageList.append(ciContext.createCGImage(output, from: output.extent)!)
        median2ndStepImageList.removeAll()
        // ３段階目メディアンリスト作成
        medianImageFilter.inputList = median3rdStepImageList.map { CIImage(cgImage: $0) }
        guard let output = medianImageFilter.outputImage else { return nil }
        if median3rdStepImageList.count >= MedianImageFilter.imageCountNeeded {
            median3rdStepImageList.removeFirst()
        }
        
        return ciContext.createCGImage(output, from: output.extent)
    }
    
    /// 物体のマスク画像生成
    func createMaskImage(segmentedMap: MLMultiArray) -> CIImage? {
        
        let size = segmentedMap.shape[0].intValue * segmentedMap.shape[1].intValue
        assert(size == (Const.imageSize * Const.imageSize))
        
        // 目的の物体のラベルを白(255)、それ以外を黒(0)とする画素値配列を作る
        var pixels = [UInt8](repeating: 0, count: size)
        for i in 0 ..< size {
            pixels[i] = segmentedMap[i].intValue == Const.objectLabel ? 255 : 0
        }
        
        // 画素値配列からマスク画像生成
        guard let segmentedImage = createCGImage(from: &pixels, width: Const.imageSize, height: Const.imageSize) else {
            return nil
        }
        
        // 膨張・収縮処理（クロージング）
        morphologyDilateFilter.inputImage = CIImage(cgImage: segmentedImage)
        morphologyDilateFilter.radius = Const.morphologyClosingRadius
        guard let dilateImage = morphologyDilateFilter.outputImage else { return nil }
        
        morphologyErodeFilter.inputImage = dilateImage
        morphologyErodeFilter.radius = Const.morphologyClosingRadius
        guard let closingImage = morphologyErodeFilter.outputImage else { return nil }
        
        // 収縮・膨張処理（オープニング）
        morphologyErodeFilter.inputImage = closingImage
        morphologyErodeFilter.radius = Const.morphologyOpeningRadius
        guard let erodeImage = morphologyErodeFilter.outputImage else { return nil }
        
        morphologyDilateFilter.inputImage = erodeImage
        morphologyDilateFilter.radius = Const.morphologyOpeningRadius
        guard let openingImage = morphologyDilateFilter.outputImage else { return nil }
        
        return openingImage
    }
    
    /// マスク画像とメディアン画像から光学迷彩画像を生成
    func createOpticalCamouflageImage(mask: CIImage, median: CGImage) -> CGImage? {
        // マスク画像からハイトマップ生成
        heightFieldFilter.setValue(mask, forKey: kCIInputImageKey)
        heightFieldFilter.setValue(NSNumber(value: Const.heightFieldRadius), forKey: kCIInputRadiusKey)
        guard let heightFieldImage = heightFieldFilter.outputImage else { return nil }
        
        // 光学迷彩化（背景とハイトマップをミックス）
        shaderMaterialFilter.setValue(heightFieldImage, forKey: kCIInputImageKey)
        shaderMaterialFilter.setValue(CIImage(cgImage: median), forKey: kCIInputShadingImageKey)
        shaderMaterialFilter.setValue(NSNumber(value: Const.shaderMaterialScale), forKey: kCIInputScaleKey)
        guard let shaderOutput = shaderMaterialFilter.outputImage else { return nil }
        
        // 光学迷彩画像のマスク部分を抽出
        multiplyCompositingFilter.setValue(shaderOutput, forKey: kCIInputImageKey)
        multiplyCompositingFilter.setValue(mask, forKey: kCIInputBackgroundImageKey)
        guard let opticalObject = multiplyCompositingFilter.outputImage else { return nil }
        
        // 背景と光学迷彩オブジェクトを合成
        compositeFilter.input1 = opticalObject
        compositeFilter.input2 = CIImage(cgImage: median)
        guard let opticalCamouflageImage = compositeFilter.outputImage else { return nil }
        
        return ciContext.createCGImage(opticalCamouflageImage,
                                       from: CGRect(origin: .zero, size: CGSize(width: Const.imageSize, height: Const.imageSize)))
    }
    
    /// 画素値の配列からCGImag(グレースケール)を作る
    func createCGImage(from: inout [UInt8], width: Int, height: Int) -> CGImage? {
        
        return from.withUnsafeMutableBufferPointer { pixelPointer in
            // 画素値配列をvImage_Bufferの形にする
            let sourceBuffer = vImage_Buffer(data: pixelPointer.baseAddress!,
                                             height: vImagePixelCount(height),
                                             width: vImagePixelCount(width),
                                             rowBytes: width)
            // 画像のピクセルフォーマットを定義
            guard let format = vImage_CGImageFormat(bitsPerComponent: 8,
                                                    bitsPerPixel: 8,
                                                    colorSpace: CGColorSpaceCreateDeviceGray(),
                                                    bitmapInfo: CGBitmapInfo(rawValue: 0)) else {
                return nil
            }
            // CGImageに変換
            return try? sourceBuffer.createCGImage(format: format)
        }
    }
}
