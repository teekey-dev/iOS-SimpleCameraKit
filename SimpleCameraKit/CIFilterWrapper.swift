//
//  CIFilterWrapper.swift
//
//  Created by TKang on 2017. 4. 19..
//  Copyright © 2017년 TKang. All rights reserved.
//

import Foundation
import UIKit

// MARK: - Generating LUT Filter
extension CIFilter {
    class func filterWithLUT(_ LUTImage:UIImage, dimension n: Int) -> CIFilter{
        let width : Int = (LUTImage.cgImage?.width)!
        let height : Int = (LUTImage.cgImage?.height)!
        let rowNum : Int = height/n
        let colNum : Int = width/n
        
        if (width % n != 0 || height % n != 0 || rowNum * colNum != n) {
            fatalError("Invalid LUT")
        }
        
        let bitmap : UnsafeMutablePointer<CUnsignedChar> = createRGBABitmapFromImage(LUTImage.cgImage!)!
        
        let size : Int = n * n * n * MemoryLayout<float_t>.size * 4
        let data : UnsafeMutablePointer<float_t> = malloc(size).assumingMemoryBound(to: float_t.self) as UnsafeMutablePointer<float_t>
        var bitmapOffset : Int = 0
        var z : Int = 0
        
        for _ in 0..<rowNum {
            for y in 0..<n {
                let tmp = z
                for _ in 0..<colNum {
                    for x in 0..<n {
                        let r : float_t = float_t(UInt(bitmap[bitmapOffset]))
                        let g : float_t = float_t(UInt(bitmap[bitmapOffset + 1]))
                        let b : float_t = float_t(UInt(bitmap[bitmapOffset + 2]))
                        let a : float_t = float_t(UInt(bitmap[bitmapOffset + 3]))
                        
                        let dataOffset : Int = (z*n*n + y*n + x) * 4
                        
                        data[dataOffset] = r / 255.0
                        data[dataOffset + 1] = g / 255.0
                        data[dataOffset + 2] = b / 255.0
                        data[dataOffset + 3] = a / 255.0
                        
                        bitmapOffset += 4
                    }
                    z += 1
                }
                z = tmp
            }
            z += colNum
        }
        
        free(bitmap)
        
        let filter : CIFilter = CIFilter(name: "CIColorCube")!
        
        filter.setValue(NSData.init(bytesNoCopy: data, length: size, freeWhenDone: true), forKey: "inputCubeData")
        filter.setValue(n, forKey: "inputCubeDimension")
        
        return filter
    }
    
    class private func createRGBABitmapFromImage(_ image: CGImage) -> UnsafeMutablePointer<CUnsignedChar>?{
        var context : CGContext? = nil
        var colorspace : CGColorSpace?
        var bitmap : UnsafeMutableRawPointer
        var bitmapSize: Int!
        var bytesPerRow: Int!
        
        let width : size_t = image.width
        let height : size_t = image.height
        
        bytesPerRow = width * 4
        bitmapSize = bytesPerRow * height
        
        bitmap = malloc(bitmapSize)
        
        colorspace = CGColorSpaceCreateDeviceRGB()
        if colorspace == nil {
            free(bitmap)
            return nil
        }
        
        context = CGContext.init(data: bitmap, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorspace!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        if context == nil {
            free(bitmap)
        }
        
        context?.draw(image, in: CGRect(origin: CGPoint.zero, size: CGSize(width: width, height: height)))
        
        return bitmap.assumingMemoryBound(to: CUnsignedChar.self) as UnsafeMutablePointer<CUnsignedChar>
    }
}

// MARK: - CIContext
extension CIContext {
    class func createCIContextForRenderingCIImage() -> CIContext {
        let context: CIContext = CIContext(options: [kCIContextWorkingColorSpace: CGColorSpaceCreateDeviceRGB()])
        return context
    }
}

// MARK: - CIImage Rendering
extension CIImage {
    func renderUIImage(_ context: CIContext, _ imageOrientation: UIImageOrientation) -> UIImage {
        let cgImage : CGImage = context.createCGImage(self, from: self.extent)!
        let uiImage : UIImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: imageOrientation)
        
        return uiImage
    }
    
    func renderUIImage(_ context: CIContext) -> UIImage {
        let uiImage = self.renderUIImage(context, .up)
        
        return uiImage
    }
}

// MARK: - Custom LUT
extension CIFilter {
    func processedImage(_ image: CIImage) -> CIImage{
        self.setValue(image, forKey: kCIInputImageKey)
        return self.outputImage!
    }
}

// MARK: - Image Orientation
extension UIImageOrientation {
    func convertToExifOrientation() -> Int32 {
        switch self {
        case .up:
            return 1
        case .upMirrored:
            return 2
        case .down:
            return 3
        case .downMirrored:
            return 4
        case .left:
            return 8
        case .leftMirrored:
            return 5
        case .right:
            return 6
        case .rightMirrored:
            return 7
        }
    }
}

extension Int32 {
    func convertToUIImageOrientation() -> UIImageOrientation {
        switch self {
        case 1:
            return .up
        case 2:
            return .upMirrored
        case 3:
            return .down
        case 4:
            return .downMirrored
        case 5:
            return .leftMirrored
        case 6:
            return .right
        case 7:
            return .rightMirrored
        case 8:
            return .left
        default:
            return UIImageOrientation.init(rawValue: 0)!
        }
    }
}

// MARK: - Blur
extension CIImage{
    //Spreads source pixels by an amount specified by a Gaussian distribution.
    //Default Value of input Radius is 10.00
    //Minimum 0.0 Maximum 100.0
    func gaussianblur(inputRadius: CGFloat?) -> CIImage{
        var radius : CGFloat = 10.0
        if let inputRadius = inputRadius {
            radius = inputRadius
        }
        let originalImageRect = self.extent
        //because the opaque pixels at the edges of the image blur into the transparent pixels outside the image’s extent. Applying a clamp effect before the blur filter avoids edge softening by making the original image opaque in all directions.
        let clampedImage = self.clampedToExtent()
        let gaussianBlur = CIFilter(name: "CIGaussianBlur", withInputParameters: [kCIInputImageKey: clampedImage, kCIInputRadiusKey: radius])
        var outputImage = (gaussianBlur?.outputImage)!
        //However, the blurred image will also have infinite extent. Use the following method to crop
        outputImage = outputImage.cropped(to: originalImageRect)
        
        return outputImage
    }
    //Blurs an image using a box-shaped convolution kernel.
    //Default Value of input Radius is 10.00
    //Min 1 Max 100
    func boxBlur(inputRadius: CGFloat?) -> CIImage {
        var radius : CGFloat = 10.0
        if let inputRadius = inputRadius {
            radius = inputRadius
        }
        let originalImageRect = self.extent
        let clampedImage = self.clampedToExtent()
        let boxBlur = CIFilter(name: "CIBoxBlur", withInputParameters: [kCIInputImageKey: clampedImage, kCIInputRadiusKey: radius])
        var outputImage = (boxBlur?.outputImage)!
        outputImage = outputImage.cropped(to: originalImageRect)
        
        return outputImage
    }
    //Blurs an image using a disc-shaped convolution kernel.
    //Default Value of input Radius is 8.00
    //Min 0 Max 100
    func discBlur(inputRadius: CGFloat?) -> CIImage {
        var radius : CGFloat = 8.0
        if let inputRadius = inputRadius {
            radius = inputRadius
        }
        let originalImageRect = self.extent
        let clampedImage = self.clampedToExtent()
        let discBlur = CIFilter(name: "CIDiscBlur", withInputParameters: [kCIInputImageKey: clampedImage, kCIInputRadiusKey: radius])
        var outputImage = (discBlur?.outputImage)!
        outputImage = outputImage.cropped(to: originalImageRect)
        
        return outputImage
    }
    //Blurs the source image according to the brightness levels in a mask image.
    //Input Radius Default value: 10.00 Minimum: 0.00 Maximum: 0.00 Slider minimum: 0.00 Slider maximum: 100.00 Identity: 0.00
    func maskedVariableBlur(inputRadius: CGFloat?, inputMask: CIImage) -> CIImage {
        var radius : CGFloat = 10.0
        if let inputRadius = inputRadius {
            radius = inputRadius
        }
        let originalImageRect = self.extent
        let clampedImage = self.clampedToExtent()
        let maskedVariableBlur = CIFilter(name: "CIMaskedVariableBlur", withInputParameters: [kCIInputImageKey: clampedImage, kCIInputRadiusKey: radius, kCIInputMaskImageKey: inputMask])
        var outputImage = (maskedVariableBlur?.outputImage)!
        outputImage = outputImage.cropped(to: originalImageRect)
        
        return outputImage
    }
    //Computes the median value for a group of neighboring pixels and replaces each pixel value with the median.
    func medianFilter() -> CIImage {
        let originalImageRect = self.extent
        let clampedImage = self.clampedToExtent()
        let medianBlur = CIFilter(name: "CIMedianBlur", withInputParameters: [kCIInputImageKey: clampedImage])
        var outputImage = (medianBlur?.outputImage)!
        outputImage = outputImage.cropped(to: originalImageRect)
        
        return outputImage
    }
    //Blurs an image to simulate the effect of using a camera that moves a specified angle and distance while capturing the image.
    //Radius DefaultValue 20.00, Angle Default Value 0.00
    //Radius Min 0 Max 100 Angle Min -PI Max PI
    func motionBlur(inputRadius: CGFloat?, inputAngle: CGFloat?) -> CIImage{
        var radius : CGFloat = 20.0
        if let inputRadius = inputRadius {
            radius = inputRadius
        }
        var angle : CGFloat = 10.0
        if let inputAngle = inputAngle {
            angle = inputAngle
        }
        let motionblur = CIFilter(name: "CIMotionBlur", withInputParameters: [kCIInputImageKey: self, kCIInputRadiusKey: radius, kCIInputAngleKey: angle])
        return (motionblur?.outputImage)!
    }
    //Reduces noise using a threshold value to define what is considered noise.
    //NoiseLevel Default Value 0.02, Sharpness Default Value 0.40
    //NoiseLevel Min 0 SliderMax 0.1, Sharpness Min 0 Max 2
    func noiseReduction(inputNoiseLevel: CGFloat?, inputSharpness: CGFloat?) -> CIImage {
        var noiseLevel : CGFloat = 0.02
        if let inputNoiseLevel = inputNoiseLevel {
            noiseLevel = inputNoiseLevel
        }
        var sharpness : CGFloat = 0.4
        if let inputSharpness = inputSharpness {
            sharpness = inputSharpness
        }
        let noiseReduction = CIFilter(name: "CINoiseReduction", withInputParameters: [kCIInputImageKey: self, "inputNoiseLevel": noiseLevel, kCIInputSharpnessKey: sharpness])
        return (noiseReduction?.outputImage)!
    }
    //Simulates the effect of zooming the camera while capturing the image.
    //Center Default [150 150], Amount Default 20.0
    //Amount Min 0 Amount Max 200
    func zoomBlur(inputCenterX: CGFloat?, inputCenterY: CGFloat?, inputAmount: CGFloat?) -> CIImage {
        var centerX : CGFloat = 150.0
        if let inputCenterX = inputCenterX {
            centerX = inputCenterX
        }
        var centerY : CGFloat = 150.0
        if let inputCenterY = inputCenterY {
            centerY = inputCenterY
        }
        var amount : CGFloat = 20.0
        if let inputAmount = inputAmount {
            amount = inputAmount
        }
        let centerVector = CIVector(x: centerX, y: centerY)
        let zoomBlur = CIFilter(name: "CIZoomBlur", withInputParameters: [kCIInputImageKey: self, kCIInputCenterKey: centerVector, "inputAmount": amount])
        return (zoomBlur?.outputImage)!
    }
}

// MARK: - Color Adjustment
extension CIImage{
    //Modifies color values to keep them within a specified range.
    //inputMinComponents RGBA values for the lower end of the range. Default Value: [0 0 0 0] Identity: [0 0 0 0]
    //inputMaxComponents RGBA values for the upper end of the range. Default Value: [1 1 1 1] Identity: [1 1 1 1]
    func colorClamp(minR: CGFloat?, minG: CGFloat?, minB: CGFloat?, minA: CGFloat?, maxR:CGFloat?, maxG:CGFloat?, maxB:CGFloat?, maxA:CGFloat?) -> CIImage {
        var minValues : [CGFloat] = [0,0,0,0]
        var maxValues : [CGFloat] = [0,0,0,0]
        if let minR = minR {
            minValues[0] = minR
        }
        if let minG = minG {
            minValues[1] = minG
        }
        if let minB = minB {
            minValues[2] = minB
        }
        if let minA = minA {
            minValues[3] = minA
        }
        if let maxR = maxR {
            maxValues[0] = maxR
        }
        if let maxG = maxG {
            maxValues[1] = maxG
        }
        if let maxB = maxB {
            maxValues[2] = maxB
        }
        if let maxA = maxA {
            maxValues[3] = maxA
        }
        let minVector = CIVector(x: minValues[0], y: minValues[1], z: minValues[2], w: minValues[3])
        let maxVector = CIVector(x: maxValues[0], y: maxValues[1], z: maxValues[2], w: maxValues[3])
        let colorClamp = CIFilter(name: "CIColorClamp", withInputParameters: [kCIInputImageKey:self, "inputMinComponents": minVector, "inputMaxComponents": maxVector])
        return (colorClamp?.outputImage)!
    }
    //Adjusts saturation, brightness, and contrast values.
    //Saturation Default value: 1.00, Contrast Default value: 1.00
    //Saturation Min 0 Max 2 Identity 1, Brightness Min -1 Max 1 Identity 0, Contrast Min 0 Max 4 SliderMin 0.25 Identity 1
    func colorControls(inputSaturation: CGFloat?, inputBrightness: CGFloat?, inputContrast: CGFloat?) -> CIImage {
        var saturation : CGFloat = 1.0
        if let inputSaturation = inputSaturation {
            saturation = inputSaturation
        }
        var brightness : CGFloat = 0.0
        if let inputBrightness = inputBrightness {
            brightness = inputBrightness
        }
        var contrast : CGFloat = 1.0
        if let inputContrast = inputContrast {
            contrast = inputContrast
        }
        let colorControls = CIFilter(name: "CIColorControls", withInputParameters: [kCIInputImageKey: self, kCIInputSaturationKey: saturation, kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast])
        return (colorControls?.outputImage)!
    }
    // Multiplies source color values and adds a bias factor to each color component.
    // Default r = 1, g = 1, b = 1, a = 1, bias = [0,0,0,0]
    func colorMatrix(r : CGFloat?, g : CGFloat?, b : CGFloat?, a : CGFloat?, rBias: CGFloat?, gBias: CGFloat?, bBias: CGFloat?, aBias: CGFloat?) -> CIImage{
        var rVector : CIVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        var gVector : CIVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        var bVector : CIVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        var aVector : CIVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        var biasValues : [CGFloat] = [0, 0, 0, 0]
        
        if let r = r {
            rVector = CIVector(x: r, y: 0, z: 0, w: 0)
        }
        if let g = g {
            gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        }
        if let b = b {
            bVector = CIVector(x: 0, y: 0, z: b, w: 0)
        }
        if let a = a {
            aVector = CIVector(x: 0, y: 0, z: 0, w: a)
        }
        if let rBias = rBias {
            biasValues[0] = rBias
        }
        if let gBias = gBias {
            biasValues[1] = gBias
        }
        if let bBias = bBias {
            biasValues[2] = bBias
        }
        if let aBias = aBias {
            biasValues[3] = aBias
        }
        let biasVector : CIVector = CIVector(x: biasValues[0], y: biasValues[1], z: biasValues[2], w: biasValues[3])
        
        let colorMatrix = CIFilter(name: "CIColorMatrix", withInputParameters: [kCIInputImageKey: self, "inputRVector": rVector, "inputGVector": gVector, "inputBVector": bVector, "inputAVector": aVector, "inputBiasVector": biasVector])
        return (colorMatrix?.outputImage)!
    }
    //Modifies the pixel values in an image by applying a set of cubic polynomials.
    //Formula r = rCoeff[0] + rCoeff[1] * r + rCoeff[2] * r*r + rCoeff[3] * r*r*r
    //Default value: [0 1 0 0] Identity: [0 1 0 0]
    func colorPolynomial(inputRedCoefficients: CIVector?, inputGreenCoefficients: CIVector?, inputBlueCoefficients: CIVector?, inputAlphaCoefficients: CIVector?) -> CIImage{
        var redCoefficientsVector : CIVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        if let inputRedCoefficients = inputRedCoefficients {
            redCoefficientsVector = inputRedCoefficients
        }
        var greenCoefficientsVector : CIVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        if let inputGreenCoefficients = inputGreenCoefficients {
            greenCoefficientsVector = inputGreenCoefficients
        }
        var blueCoefficientsVector : CIVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        if let inputBlueCoefficients = inputBlueCoefficients {
            blueCoefficientsVector = inputBlueCoefficients
        }
        var alphaCoefficientsVector : CIVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        if let inputAlphaCoefficients = inputAlphaCoefficients {
            alphaCoefficientsVector = inputAlphaCoefficients
        }
        let colorPolynomial = CIFilter(name: "CIColorPolynomial", withInputParameters: [kCIInputImageKey: self, "inputRedCoefficients": redCoefficientsVector, "inputGreenCoefficients": greenCoefficientsVector, "inputBlueCoefficients":blueCoefficientsVector, "inputAlphaCoefficients":alphaCoefficientsVector])
        return (colorPolynomial?.outputImage)!
    }
    //Adjusts the exposure setting for an image similar to the way you control exposure for a camera when you change the F-stop.
    //EV Default value: 0.5
    //Identity : 0
    //Min -10 Max 10
    //s.rgb * pow(2.0, ev)
    func exposureAdjust(inputEV: CGFloat?) -> CIImage{
        var exposure:CGFloat = 0.5
        if let inputEV = inputEV {
            exposure = inputEV
        }
        let exposureAdjust = CIFilter(name: "CIExposureAdjust", withInputParameters: [kCIInputImageKey: self, kCIInputEVKey: exposure])
        return (exposureAdjust?.outputImage)!
    }
    //Adjusts midtone brightness.
    //Power Default value: 0.75
    //Identity 1 Min 0.25 Max 4
    //pow(s.rgb, vec3(power))
    func gammaAdjust(inputPower: CGFloat?) -> CIImage{
        var power: CGFloat = 0.75
        if let inputPower = inputPower{
            power = inputPower
        }
        let gammaAdjust = CIFilter(name: "CIGammaAdjust", withInputParameters: [kCIInputImageKey:self, "inputPower": power])
        return (gammaAdjust?.outputImage)!
    }
    //Changes the overall hue, or tint, of the source pixels.
    //Angle Default 0.0 Min -PI Max PI
    func hueAdjust(inputAngle: CGFloat?) -> CIImage {
        var angle: CGFloat = 0.0
        if let inputAngle = inputAngle {
            angle = inputAngle
        }
        let hueAdjust = CIFilter(name: "CIHueAdjust", withInputParameters: [kCIInputImageKey:self, kCIInputAngleKey:angle])
        return (hueAdjust?.outputImage)!
    }
    //Maps color intensity from a linear gamma curve to the sRGB color space.
    func linearToSRGBToneCurve() -> CIImage{
        let linearToSRGBToneCurve = CIFilter(name: "CILinearToSRGBToneCurve", withInputParameters: [kCIInputImageKey: self])
        return (linearToSRGBToneCurve?.outputImage)!
    }
    //Maps color intensity from the sRGB color space to a linear gamma curve.
    func sRGBToneCurveToLinear() -> CIImage{
        let sRGBToneCurveToLinear = CIFilter(name: "CISRGBToneCurveToLinear", withInputParameters: [kCIInputImageKey:self])
        return (sRGBToneCurveToLinear?.outputImage)!
    }
    //Adapts the reference white point for an image.
    //Neutral Default value: [6500, 0], TargetNeutral Default value: [6500, 0]
    //Neutral X is temperature which is between approximately 2000 to 15000
    //Neutral Y is tint which is between approximately -350 to 350
    //inputTemperature Identity : 0,0 inputTint Identity : 0.0
    //inputTemperature range is around -4500 ~ +8500
    //inputTint range is around -350 to 350
    func temperatureAndTint(inputTemperature: CGFloat?, inputTint: CGFloat?) -> CIImage{
        var temperature: CGFloat = 6500.0
        if let inputTemperature = inputTemperature {
            temperature += inputTemperature
        }
        var tint : CGFloat = 0.0
        if let inputTint = inputTint {
            tint = inputTint
        }
        let neutralVector = CIVector(x: temperature, y: tint)
        let targetNeutralVector = CIVector(x: 6500.0, y: 0.0)
        let temperatureAndTint = CIFilter(name: "CITemperatureAndTint", withInputParameters: [kCIInputImageKey:self, "inputNeutral":neutralVector, "inputTargetNeutral":targetNeutralVector])
        return (temperatureAndTint?.outputImage)!
    }
    //Adjusts tone response of the R, G, and B channels of an image.
    //The input points are five x,y values that are interpolated using a spline curve. The curve is applied in a perceptual (gamma 2) version of the working space.
    //Default value: [0, 0], [0.25, 0.25],  [0.5, 0.5], [0.75, 0.75], [1, 1]
    func toneCurve(inputPoint0:CIVector?, inputPoint1:CIVector?, inputPoint2:CIVector?, inputPoint3:CIVector?, inputPoint4:CIVector?) -> CIImage{
        var point0 = CIVector(x: 0.0, y: 0.0)
        if let inputPoint0 = inputPoint0 {
            point0 = inputPoint0
        }
        var point1 = CIVector(x: 0.25, y: 0.25)
        if let inputPoint1 = inputPoint1 {
            point1 = inputPoint1
        }
        var point2 = CIVector(x: 0.5, y: 0.5)
        if let inputPoint2 = inputPoint2 {
            point2 = inputPoint2
        }
        var point3 = CIVector(x: 0.75, y: 0.75)
        if let inputPoint3 = inputPoint3 {
            point3 = inputPoint3
        }
        var point4 = CIVector(x: 1.0, y: 1.0)
        if let inputPoint4 = inputPoint4 {
            point4 = inputPoint4
        }
        let toneCurve = CIFilter(name: "CIToneCurve", withInputParameters: [kCIInputImageKey:self, "inputPoint0":point0, "inputPoint1":point1, "inputPoint2":point2, "inputPoint3":point3, "inputPoint4":point4])
        return (toneCurve?.outputImage)!
    }
    //Adjusts the saturation of an image while keeping pleasing skin tones.
    //Min -1 Max 1
    func vibrance(inputAmount: CGFloat?) -> CIImage{
        var amount: CGFloat = 0.0
        if let inputAmount = inputAmount {
            amount = inputAmount
        }
        let vibrance = CIFilter(name: "CIVibrance", withInputParameters: [kCIInputImageKey:self, "inputAmount":amount])
        return (vibrance?.outputImage)!
    }
    //Adjusts the reference white point for an image and maps all colors in the source using the new reference.
    func whitePointAdjust(inputColor: CIColor) -> CIImage{
        let whitePointAdjust = CIFilter(name: "CIWhitePointAdjust", withInputParameters: [kCIInputImageKey:self, kCIInputColorKey:inputColor])
        return (whitePointAdjust?.outputImage)!
    }
}

// MARK: - Color Effect
extension CIImage {
    //Inverts the colors in an image.
    func colorInvert() -> CIImage {
        let colorInvert = CIFilter(name: "CIColorInvert", withInputParameters: [kCIInputImageKey:self])
        return (colorInvert?.outputImage)!
    }
}

// MARK: - Composite Operation
extension CIImage {
    //Places the input image over the background image, then uses the luminance of the background image to determine what to show.
    func sourceAtopCompositing(_ backgroundImage: CIImage) -> CIImage{
        let sourceAtopCompositing = CIFilter(name: "CISourceAtopCompositing", withInputParameters: [kCIInputImageKey: self, kCIInputBackgroundImageKey: backgroundImage])
        return (sourceAtopCompositing?.outputImage)!
    }
    //Places the input image over the input background image
    func sourceOverCompositing(_ backgroundImage: CIImage) -> CIImage{
        let sourceOverCompositing = CIFilter(name: "CISourceOverCompositing", withInputParameters: [kCIInputImageKey: self, kCIInputBackgroundImageKey: backgroundImage])
        return (sourceOverCompositing?.outputImage)!
    }
}

// MARK: - Geometry Adjustment
extension CIImage{
    //Applies an affine transform to an image.
    func affineTransform(inputTransform: CGAffineTransform) -> CIImage{
        let transform = NSValue(cgAffineTransform: inputTransform)
        let affineTransform = CIFilter(name:"CIAffineTransform", withInputParameters: [kCIInputImageKey:self, kCIInputTransformKey:transform])
        return (affineTransform?.outputImage)!
    }
    //Applies a crop to an image.
    func crop(inputRectangle: CIVector) -> CIImage{
        let crop = CIFilter(name: "CICrop", withInputParameters: [kCIInputImageKey:self, "inputRectangle":inputRectangle])
        return (crop?.outputImage)!
    }
    //Produces a high-quality, scaled version of a source image.
    //You typically use this filter to scale down an image.
    func lanczosScaleTransform(inputScale: CGFloat, inputAspectRatio: CGFloat) -> CIImage{
        let lanczosScaleTransform = CIFilter(name: "CILanczosScaleTransform", withInputParameters: [kCIInputImageKey:self, kCIInputScaleKey:inputScale, kCIInputAspectRatioKey:inputAspectRatio])
        return (lanczosScaleTransform?.outputImage)!
    }
    //Applies a perspective correction, transforming an arbitrary quadrilateral region in the source image to a rectangular output image.
    //The extent of the rectangular output image varies based on the size and placement of the specified quadrilateral region in the input image.
    func perspectiveCorrection(inputTopLeft: CIVector, inputTopRight: CIVector, inputBottomLeft: CIVector, inputBottomRight: CIVector) -> CIImage{
        let perspectiveCorrection = CIFilter(name: "CIPerspectiveCorrection", withInputParameters: [kCIInputImageKey:self, "inputTopLeft": inputTopLeft, "inputTopRight":inputTopRight, "inputBottomRight": inputBottomRight, "inputBottomLeft":inputBottomLeft])
        return (perspectiveCorrection?.outputImage)!
    }
    //Alters the geometry of an image to simulate the observer changing viewing position.
    //You can use the perspective filter to skew an image.
    func perspectiveTransform(inputTopLeft: CIVector, inputTopRight: CIVector, inputBottomLeft: CIVector, inputBottomRight: CIVector) -> CIImage{
        let perspectiveTransform = CIFilter(name: "CIPerspectiveTransform", withInputParameters: [kCIInputImageKey:self, "inputTopLeft": inputTopLeft, "inputTopRight":inputTopRight, "inputBottomRight": inputBottomRight, "inputBottomLeft":inputBottomLeft])
        return (perspectiveTransform?.outputImage)!
    }
    //Alters the geometry of a portion of an image to simulate the observer changing viewing position.
    //You can use the perspective filter to skew an the portion of the image defined by extent. See CIPerspectiveTransform for an example of the output of this filter when you supply the input image size as the extent.
    func perspectiveTransformWithExtent(inputExtent: CIVector, inputTopLeft: CIVector, inputTopRight: CIVector, inputBottomLeft: CIVector, inputBottomRight: CIVector) -> CIImage {
        let perspectiveTransformWithExtent = CIFilter(name: "CIPerspectiveTransformWithExtent", withInputParameters: [kCIInputImageKey:self, kCIInputExtentKey: inputExtent , "inputTopLeft": inputTopLeft, "inputTopRight":inputTopRight, "inputBottomRight": inputBottomRight, "inputBottomLeft":inputBottomLeft])
        return (perspectiveTransformWithExtent?.outputImage)!
    }
    //Rotates the source image by the specified angle in radians.
    //The image is scaled and cropped so that the rotated image fits the extent of the input image.
    func straightenFilter(inputAngle: CGFloat) -> CIImage {
        let straightenFilter = CIFilter(name: "CIStraightenFilter", withInputParameters: [kCIInputImageKey:self, kCIInputAngleKey: inputAngle])
        return (straightenFilter?.outputImage)!
    }
}
// MARK: - Gradient
extension CIImage {
    // Generates a gradient that varies radially between two circles having the same center.
    static func radialGradient(inputCenter: CIVector, inputRadius0:CGFloat, inputRadius1: CGFloat, inputColor0: CIColor, inputColor1: CIColor) -> CIImage{
        let radialGradient = CIFilter(name: "CIRadialGradient", withInputParameters: [kCIInputCenterKey: inputCenter,
                                                                                      "inputRadius0": inputRadius0,
                                                                                      "inputRadius1": inputRadius1,
                                                                                      "inputColor0": inputColor0,
                                                                                      "inputColor1": inputColor1])
        return (radialGradient?.outputImage)!
    }
    
    // Generates a gradient that uses an S-curve function to blend colors along a linear axis between two defined endpoints.
    static func smoothLinearGradient(inputPoint0: CIVector, inputPoint1: CIVector, inputColor0: CIColor, inputColor1: CIColor) -> CIImage {
        let smoothLinearGradient = CIFilter(name: "CISmoothLinearGradient", withInputParameters: ["inputPoint0": inputPoint0,
                                                                                                  "inputPoint1": inputPoint1,
                                                                                                  "inputColor0": inputColor0,
                                                                                                  "inputColor1": inputColor1])
        return (smoothLinearGradient?.outputImage)!
    }
    
}

// MARK: - Sharpen
extension CIImage {
    //Increases image detail by sharpening.
    //Default Value of input sharpness is 0.40
    //Min 0 Max 2
    func sharpenLuminance(inputSharpness: CGFloat?) -> CIImage{
        var sharpness : CGFloat = 0.4
        if let inputSharpness = inputSharpness {
            sharpness = inputSharpness
        }
        let sharpenLuminance = CIFilter(name: "CISharpenLuminance", withInputParameters: [kCIInputImageKey:self, kCIInputSharpnessKey:sharpness])
        return (sharpenLuminance?.outputImage)!
    }
    //Increases the contrast of the edges between pixels of different colors in an image.
    //inputRadius Default value: 2.50, inputIntensity Default value: 0.50
    func unsharpMask(inputRadius: CGFloat?, inputIntensity: CGFloat?) -> CIImage {
        var radius : CGFloat = 2.5
        if let inputRadius = inputRadius {
            radius = inputRadius
        }
        var intensity : CGFloat = 0.5
        if let inputIntensity = inputIntensity {
            intensity = inputIntensity
        }
        let unsharpMask = CIFilter(name: "CIUnsharpMask", withInputParameters: [kCIInputImageKey:self, kCIInputRadiusKey: radius ,kCIInputIntensityKey: intensity])
        return (unsharpMask?.outputImage)!
    }
}

// MARK: - Stylize 
extension CIImage {
    // Uses alpha values from a mask to interpolate between an image and the background.
    func blendWithAlphaMask(inputBackgroundImage: CIImage, inputMaskImage: CIImage) -> CIImage {
        let blendWithAlphaMask = CIFilter(name: "CIBlendWithAlphaMask", withInputParameters: [kCIInputImageKey: self,
                                                                                              kCIInputBackgroundImageKey: inputBackgroundImage,
                                                                                              kCIInputMaskImageKey: inputMaskImage])
        return (blendWithAlphaMask?.outputImage)!
    }
    
    // Uses values from a grayscale mask to interpolate between an image and the background.
    func blendWithMask(inputBackgroundImage: CIImage, inputMaskImage: CIImage) -> CIImage {
        let blendWithMask = CIFilter(name: "CIBlendWithMask", withInputParameters: [kCIInputImageKey: self,
                                                                                    kCIInputBackgroundImageKey: inputBackgroundImage,
                                                                                    kCIInputMaskImageKey: inputMaskImage])
        return (blendWithMask?.outputImage)!
    }
    
    //Adjust the tonal mapping of an image while preserving spatial detail.
    //HighlightAmount Default 1.00 Identity 1.00 min 0 max 1 slider min 0.3 slidermax 1
    //ShadowAmount Default 0.00 Identity 0.00 min -1 max 1
    func highlightShadowAdjust(inputHighlightAmount: CGFloat?, inputShadowAmount: CGFloat?) -> CIImage {
        var highlight : CGFloat = 1.0
        if let inputHighlightAmount = inputHighlightAmount {
            highlight = inputHighlightAmount
        }
        var shadow : CGFloat = 0.0
        if let inputShadowAmount = inputShadowAmount {
            shadow = inputShadowAmount
        }
        let highlightShadowAdjust = CIFilter(name: "CIHighlightShadowAdjust", withInputParameters: [kCIInputImageKey:self, "inputHighlightAmount": highlight, "inputShadowAmount": shadow])
        return (highlightShadowAdjust?.outputImage)!
    }
}

// MARK: - Transition
extension CIImage {
    //Transitions from one image to another of differing dimensions by unfolding and crossfading.
    // bottom height is fixed to 0.0
    // number of folds min 1.0 max 50.0. Identity 0.0, slider min 0.0, slider max 10.0, default 3.0
    // fold shadow amount min 0.0, max 1.0, default 0.1, identitty 0.0
    // input time min 0.0 max 1.0, default 0.0, identity 0.0
    func accordionFoldTransition(inputTargetImage: CIImage, inputBottomHeight: CGFloat = 0.0, inputNumberOfFolds: CGFloat = 3.0, inputFoldShadowAmount: CGFloat = 0.1, inputTime: CGFloat = 0.0) -> CIImage {
        let accordionFoldTransition = CIFilter(name: "CIAccordionFoldTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                                        kCIInputTargetImageKey: inputTargetImage,
                                                                                                        "inputBottomHeight": inputBottomHeight,
                                                                                                        "inputNumberOfFolds": inputNumberOfFolds,
                                                                                                        "inputFoldShadowAmount": inputFoldShadowAmount,
                                                                                                        kCIInputTimeKey: inputTime])
        return (accordionFoldTransition?.outputImage)!
    }
    
    // Uses a dissolve to transition from one image to another.
    // input time default 0.0
    func dissolveTransition(inputTargetImage: CIImage, inputTime: CGFloat = 0.0) -> CIImage {
        let dissolveTransition = CIFilter(name: "CIDissolveTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                              kCIInputTargetImageKey: inputTargetImage,
                                                                                              kCIInputTimeKey: inputTime])
        return (dissolveTransition?.outputImage)!
    }
    
    // Transitions from one image to another by passing a bar over the source image.
    // input angle default = 3.14, input width default = 30.0, input bar offset default = 10.0, input time default = 0.0
    func barsSwipeTransition(inputTargetImage: CIImage, inputAngle: CGFloat = 3.14, inputWidth: CGFloat = 30.0, inputBarOffset: CGFloat = 10.0, inputTime: CGFloat = 0.0) -> CIImage {
        let barsSwipeTransition = CIFilter(name: "CIBarsSwipeTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                                kCIInputTargetImageKey: inputTargetImage,
                                                                                                kCIInputAngleKey: inputAngle,
                                                                                                kCIInputWidthKey: inputWidth,
                                                                                                "inputBarOffset": inputBarOffset,
                                                                                                kCIInputTimeKey: inputTime])
        return (barsSwipeTransition?.outputImage)!
    }
    
    // Transitions from one image to another by simulating the effect of a copy machine.
    // inputExtent default = [0 0 300 300], input time default = 0.0, input angle default = 0.0, input width default = 200.0, input opacity default = 1.3
    func copyMachineTransition(inputTargetImage: CIImage, inputExtent: CIVector = CIVector(x: 0, y: 0, z: 300, w: 300), inputColor: CIColor = CIColor.white, inputTime: CGFloat = 0.0, inputAngle: CGFloat = 0.0, inputWidth: CGFloat = 0.0, inputOpacity: CGFloat = 1.30) -> CIImage{
        let copyMachineTransition = CIFilter(name: "CICopyMachineTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                                    kCIInputTargetImageKey: inputTargetImage,
                                                                                                    kCIInputExtentKey: inputExtent,
                                                                                                    kCIInputColorKey: inputColor,
                                                                                                    kCIInputTimeKey: inputTime,
                                                                                                    kCIInputAngleKey: inputAngle,
                                                                                                    kCIInputWidthKey: inputWidth,
                                                                                                    "inputOpacity": inputOpacity])
        return (copyMachineTransition?.outputImage)!
    }
    
    // Transitions from one image to another using the shape defined by a mask.
    // input time default = 0.0, input shadow radius = 8.0, input shadow density default = 0.65, input shadow offset default = [0, -10]
    func disintegrateWithMaskTransition(inputTargetImage: CIImage, inputMaskImage: CIImage, inputTime: CGFloat = 0.0, inputShadowRadius: CGFloat = 8.0, inputShadowDensity: CGFloat = 0.65, inputShadowOffset: CIVector = CIVector(x: 0, y: -10)) -> CIImage {
        let disintegrateWithMaskTransition = CIFilter(name: "CIDisintegrateWithMaskTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                                                      kCIInputTargetImageKey: inputTargetImage,
                                                                                                                      kCIInputMaskImageKey: inputMaskImage,
                                                                                                                      kCIInputTimeKey: inputTime,
                                                                                                                      "inputShadowRadius": inputShadowRadius,
                                                                                                                      "inputShadowDensity": inputShadowDensity,
                                                                                                                      "inputShadowOffset": inputShadowOffset])
        return (disintegrateWithMaskTransition?.outputImage)!
    }
    
    // Transitions from one image to another by creating a flash.
    func flashTransition(inputTargetImage : CIImage, inputCenter: CIVector = CIVector(x: 150, y: 150), inputExtent: CIVector = CIVector(x: 0, y: 0, z: 300, w: 300), inputColor: CIColor = CIColor.white, inputTime: CGFloat, inputMaxStriationRadius: CGFloat = 2.58, inputStriationStrength: CGFloat = 0.5, inputStriationContrast: CGFloat = 1.38, inputFadeThreshold: CGFloat = 0.85) -> CIImage {
        let flashTransition = CIFilter(name: "CIFlashTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                        kCIInputTargetImageKey: inputTargetImage,
                                                                                        kCIInputCenterKey: inputCenter,
                                                                                        kCIInputExtentKey: inputExtent,
                                                                                        kCIInputColorKey: inputColor,
                                                                                        kCIInputTimeKey: inputTime,
                                                                                        "inputMaxStriationRadius": inputMaxStriationRadius,
                                                                                        "inputStriationStrength": inputStriationStrength,
                                                                                        "inputStriationContrast": inputStriationContrast,
                                                                                        "inputFadeThreshold": inputFadeThreshold])
        
        return (flashTransition?.outputImage)!
    }
    
    // Transitions from one image to another by revealing the target image through irregularly shaped holes.
    func modTransition(inputTargetImage: CIImage, inputCenter: CIVector = CIVector(x: 150, y: 150), inputTime: CGFloat = 0.0, inputAngle: CGFloat = 2.00, inputRadius: CGFloat = 150.0, inputCompression: CGFloat = 300.0) -> CIImage {
        let modTransition = CIFilter(name: "CIModTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                    kCIInputTargetImageKey: inputTargetImage,
                                                                                    kCIInputCenterKey: inputCenter,
                                                                                    kCIInputAngleKey: inputAngle,
                                                                                    kCIInputRadiusKey: inputRadius,
                                                                                    "inputCompression": inputCompression])
        return (modTransition?.outputImage)!
    }
    
    // Transitions from one image to another by simulating a curling page, revealing the new image as the page curls.
    func pageCurlTransition(inputTargetImage: CIImage!, inputBacksideImage: CIImage, inputShadingImage: CIImage, inputExtent: CIVector = CIVector(x: 0, y: 0, z: 300, w: 300), inputTime: CGFloat = 0.0, inputAngle: CGFloat = 0.0, inputRadius: CGFloat = 0.0) -> CIImage {
        let pageCurlTransition = CIFilter(name: "CIPageCurlTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                              kCIInputTargetImageKey: inputTargetImage,
                                                                                              "inputBacksideImage": inputBacksideImage,
                                                                                              "inputShadingImage": inputShadingImage,
                                                                                              kCIInputExtentKey: inputExtent,
                                                                                              kCIInputTimeKey: inputTime,
                                                                                              kCIInputAngleKey: inputAngle,
                                                                                              kCIInputRadiusKey: inputRadius])
        return (pageCurlTransition?.outputImage)!
    }
    
    // Transitions from one image to another by simulating a curling page, revealing the new image as the page curls.
    // input extent identity = (null)
    // input angle min -3.14 max 3.14 identity  0.0
    // input radius min 0.01 max 0.0 slider min 0.01 slider max 400 identity 0 ??
    // input shadow size min 0.0 max 1.0 identity 0.0
    // input shadow amout min 0 max 1.0 identity 0.0
    // input shadow extent identity (null)
    func pageCurlWithShadowTransition(inputTargetImage: CIImage, inputBacksideImage: CIImage, inputExtent: CIVector = CIVector(x: 0, y: 0, z: 0, w: 0), inputTime: CGFloat = 0.0, inputAngle: CGFloat = 0.0, inputRadius: CGFloat = 100.0, inputShadowSize: CGFloat = 0.5, inputShadowAmount: CGFloat = 0.7, inputShadowExtent : CIVector = CIVector(x: 0, y: 0, z: 0, w: 0)) -> CIImage {
        let pageCurlWithShadowTransition = CIFilter(name: "CIPageCurlWithShadowTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                                                  kCIInputTargetImageKey: inputTargetImage,
                                                                                                                  "inputBacksideImage": inputBacksideImage,
                                                                                                                  kCIInputExtentKey: inputExtent,
                                                                                                                  kCIInputTimeKey: inputTime,
                                                                                                                  kCIInputAngleKey: inputAngle,
                                                                                                                  kCIInputRadiusKey: inputRadius,
                                                                                                                  "inputShadowSize": inputShadowSize,
                                                                                                                  "inputShadowAmount": inputShadowAmount,
                                                                                                                  "inputShadowExtent": inputShadowExtent])
        return (pageCurlWithShadowTransition?.outputImage)!
    }
    
    // Transitions from one image to another by creating a circular wave that expands from the center point, revealing the new image in the wake of the wave.
    func rippleTransition(inputTargetImage: CIImage, inputShadingImage: CIImage, inputCenter: CIVector = CIVector(x: 150, y: 150), inputExtent: CIVector = CIVector(x: 0, y: 0, z: 300, w: 300), inputTime : CGFloat = 0.0, inputWidth : CGFloat = 100.0, inputScale: CGFloat = 100.0) -> CIImage {
        let rippleTransition = CIFilter(name:"CIRippleTransition", withInputParameters:[kCIInputImageKey: self,
                                                                                        kCIInputTargetImageKey: inputTargetImage,
                                                                                        kCIInputShadingImageKey: inputShadingImage,
                                                                                        kCIInputCenterKey: inputCenter,
                                                                                        kCIInputExtentKey: inputExtent,
                                                                                        kCIInputTimeKey: inputTime,
                                                                                        kCIInputWidthKey: inputWidth,
                                                                                        kCIInputScaleKey: inputScale])
        return (rippleTransition?.outputImage)!
    }
    
    // Transitions from one image to another by simulating a swiping action.
    func swipeTransition(inputTargetImage: CIImage, inputExtent: CIVector = CIVector(x: 0, y: 0, z: 300, w: 300), inputColor : CIColor = CIColor.white, inputTime: CGFloat = 0.0, inputAngle: CGFloat = 0.0, inputWidth : CGFloat = 300.0, inputOpacity : CGFloat = 0.0) -> CIImage {
        let swipeTransition = CIFilter(name: "CISwipeTransition", withInputParameters: [kCIInputImageKey: self,
                                                                                        kCIInputTargetImageKey: inputTargetImage,
                                                                                        kCIInputExtentKey: inputExtent,
                                                                                        kCIInputColorKey: inputColor,
                                                                                        kCIInputTimeKey: inputTime,
                                                                                        kCIInputAngleKey: inputAngle,
                                                                                        kCIInputWidthKey: inputWidth,
                                                                                        "inputOpacity": inputOpacity])
        return (swipeTransition?.outputImage)!
    }
}
