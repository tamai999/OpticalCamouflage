import UIKit

fileprivate struct Const {
    static let imageCountNeeded = 5
}

class MedianImageFilter: CIFilter {

    var inputList: [CIImage]?
    static var imageCountNeeded: Int {
        return Const.imageCountNeeded
    }
    
    private static var ciKernel: CIColorKernel?
    
    override init() {
        super.init()
        
        if Self.ciKernel == nil {
            guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else { return }
            do {
                let data = try Data(contentsOf: url)
                Self.ciKernel = try CIColorKernel(functionName: "median", fromMetalLibraryData: data)
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
            guard let inputList = inputList,
                  inputList.count == Const.imageCountNeeded,
                  let kernel = Self.ciKernel else { return nil }

            let roiCallback: CIKernelROICallback = { (index, destRect) in
                return destRect
            }
            return kernel.apply(extent: inputList[0].extent,
                                roiCallback: roiCallback,
                                arguments: [
                                    inputList[0],inputList[1],inputList[2],inputList[3],inputList[4]
                                ])
        }
    }
}
