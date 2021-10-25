import UIKit

class CompositeFilter: CIFilter {

    var input1: CIImage?
    var input2: CIImage?
    
    private static var ciKernel: CIColorKernel?
    
    override init() {
        super.init()
        
        if Self.ciKernel == nil {
            guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else { return }
            do {
                let data = try Data(contentsOf: url)
                Self.ciKernel = try CIColorKernel(functionName: "composite", fromMetalLibraryData: data)
            } catch  {
                return
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var outputImage : CIImage? {
        get {
            guard let input1 = input1,
                  let input2 = input2,
                  let kernel = Self.ciKernel else { return nil }

            let roiCallback: CIKernelROICallback = { (index, destRect) in
                return destRect
            }
            return kernel.apply(extent: input1.extent,
                                roiCallback: roiCallback,
                                arguments: [
                                    input1, input2
                                ])
        }
    }
}

