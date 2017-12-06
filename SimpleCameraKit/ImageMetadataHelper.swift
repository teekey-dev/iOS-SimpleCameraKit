//
//  ImageMetadataHelper.swift
//  nineEdit
//
//  Created by TKang on 2017. 6. 13..
//  Copyright © 2017년 TKang. All rights reserved.
//

import UIKit
import ImageIO
import MobileCoreServices

enum ExifOrientation : Int {
    case unknown, up, upMirrored, upsideDown, upsideDownMirrored, leftMirrored, left, rightMirrored, right
}

extension Data {
    func getMetadata() -> [String: Any]? {
        let imageSource = CGImageSourceCreateWithData(self as CFData, nil)
        if let imageSource = imageSource {
            let options: [String: Any] = [kCGImageSourceShouldCache as String: false]
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, options as CFDictionary)
            
            return imageProperties as? [String: Any]
        } else {
            print("failed to read metadata")
            return nil
        }
    }
    
    func setMetadata(with metadata:[String:Any]) -> Data{
        let source = CGImageSourceCreateWithData(self as CFData, nil)!
        let imageData = CFDataCreateMutable(nil, 0)!
        let destination = CGImageDestinationCreateWithData(imageData, kUTTypeJPEG, 1, nil)!
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        CGImageDestinationFinalize(destination)
        
        return imageData as Data
    }
    
    func setMetadata(with metadata:[String:Any], comment: String?, software: String?) -> Data {
        let newMetadata = metadata.changeMetadata(with: nil, comment: comment, software: software, exifOrientation: nil)
        
        return setMetadata(with: newMetadata)
    }
    
    func setMetadata(with metadata:[String:Any], comment: String?, software: String?, exifOrientation: ExifOrientation?) -> Data {
        let newMetadata = metadata.changeMetadata(with: nil, comment: comment, software: software, exifOrientation: exifOrientation)
        
        return setMetadata(with: newMetadata)
    }
    
    func changeMetadata(metadata: [String: Any], imageSize: CGSize?, comment: String?, software: String?, exifOrientation: ExifOrientation?) -> [String: Any] {
        var newMetadata = metadata
        var exifdata: [String:Any]? = metadata[kCGImagePropertyExifDictionary as String] as? [String:Any]
        var tiffdata: [String:Any]? = metadata[kCGImagePropertyTIFFDictionary as String] as? [String:Any]
        if exifdata == nil {
            exifdata = [String:Any]()
        }
        if tiffdata == nil {
            tiffdata = [String:Any]()
        }
        
        if let imageSize = imageSize {
            newMetadata.updateValue(imageSize.width, forKey: kCGImagePropertyPixelWidth as String)
            newMetadata.updateValue(imageSize.height, forKey: kCGImagePropertyPixelHeight as String)
            exifdata!.updateValue(imageSize.width, forKey: kCGImagePropertyExifPixelXDimension as String)
            exifdata!.updateValue(imageSize.height, forKey: kCGImagePropertyExifPixelYDimension as String)
        }
        
        if let comment = comment {
            exifdata!.updateValue(comment, forKey: kCGImagePropertyExifUserComment as String)
        }
        
        if let software = software {
            tiffdata!.updateValue(software, forKey: kCGImagePropertyTIFFSoftware as String)
        }
        
        if let exifOrientation = exifOrientation {
            newMetadata.updateValue(exifOrientation.rawValue, forKey: kCGImagePropertyOrientation as String)
            tiffdata!.updateValue(exifOrientation.rawValue, forKey: kCGImagePropertyTIFFOrientation as String)
        }
        
        newMetadata.updateValue(exifdata!, forKey: kCGImagePropertyExifDictionary as String)
        newMetadata.updateValue(tiffdata!, forKey: kCGImagePropertyTIFFDictionary as String)
        
        return newMetadata
    }
}

extension Dictionary {
    func changeMetadata(with imageSize: CGSize?, comment: String?, software: String?, exifOrientation: ExifOrientation?) -> [String: Any] {
        var newMetadata = self as! [String:Any]
        var exifdata: [String:Any]? = newMetadata[kCGImagePropertyExifDictionary as String] as? [String:Any]
        var tiffdata: [String:Any]? = newMetadata[kCGImagePropertyTIFFDictionary as String] as? [String:Any]
        if exifdata == nil {
            exifdata = [String:Any]()
        }
        if tiffdata == nil {
            tiffdata = [String:Any]()
        }
        
        if let imageSize = imageSize {
            newMetadata.updateValue(imageSize.width, forKey: kCGImagePropertyPixelWidth as String)
            newMetadata.updateValue(imageSize.height, forKey: kCGImagePropertyPixelHeight as String)
            exifdata!.updateValue(imageSize.width, forKey: kCGImagePropertyExifPixelXDimension as String)
            exifdata!.updateValue(imageSize.height, forKey: kCGImagePropertyExifPixelYDimension as String)
        }
        
        if let comment = comment {
            exifdata!.updateValue(comment, forKey: kCGImagePropertyExifUserComment as String)
        }
        
        if let software = software {
            tiffdata!.updateValue(software, forKey: kCGImagePropertyTIFFSoftware as String)
        }
        
        if let exifOrientation = exifOrientation {
            newMetadata.updateValue(exifOrientation.rawValue, forKey: kCGImagePropertyOrientation as String)
            tiffdata!.updateValue(exifOrientation.rawValue, forKey: kCGImagePropertyTIFFOrientation as String)
        }
        
        newMetadata.updateValue(exifdata!, forKey: kCGImagePropertyExifDictionary as String)
        newMetadata.updateValue(tiffdata!, forKey: kCGImagePropertyTIFFDictionary as String)
        
        return newMetadata
    }
    
    func removeGeoTag() -> [String:Any] {
        var newMetadata = self as! [String:Any]
        newMetadata.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
        
        return newMetadata
    }
}
