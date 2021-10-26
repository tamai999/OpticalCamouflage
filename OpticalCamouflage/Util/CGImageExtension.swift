import UIKit

extension CGImage {
    static func monoColor(_ color: UIColor, size: CGSize) -> CGImage? {
        guard let colorGenerator = CIFilter(name: "CIConstantColorGenerator") else { return nil }
        colorGenerator.setValue(CIColor(color: color), forKey: kCIInputColorKey)
        guard let monoColor = colorGenerator.outputImage else { return nil }
        
        return CIContext().createCGImage(monoColor, from: CGRect(origin: .zero, size: size))
    }
}
