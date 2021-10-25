import UIKit
import CoreImage.CIFilterBuiltins

extension CIImage {
    func crop(frame: CGRect) -> CIImage? {
        guard let cropFilter = CIFilter(name: "CICrop") else { return nil }
        cropFilter.setValue(self, forKey: kCIInputImageKey)
        let vector = CIVector(cgRect: frame)
        cropFilter.setValue(vector, forKey: "inputRectangle")
        return cropFilter.outputImage
    }
}
