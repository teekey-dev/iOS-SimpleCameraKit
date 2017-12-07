//
//  ViewController.swift
//  SimpleCameraKit
//
//  Created by TKang on 2017. 10. 12..
//  Copyright © 2017년 TKang. All rights reserved.
//

import UIKit
import Photos

class ViewController: UIViewController {
    
    @IBOutlet weak var cameraPreview: UIView!
    
    var camera : SimpleCamera!
    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        camera = SimpleCamera()
        camera.setPreview(to: self.cameraPreview)
        camera.delegate = self
        camera.start()
    
    }

    @IBAction func buttonTapped(_ sender: Any) {
        camera.capturePhoto()
    }
    
    @IBAction func captureScreenButtonTapped(_ sender: Any) {
        camera.captureCurrentScreen()
    }
    
    @IBAction func changeCamera(_ sender: Any) {
        camera.rotateCamera()
    }
}

extension ViewController: SimpleCameraDelegate {
    func simpleCameraDidChangeDeviceOrientation(_ camera: SimpleCamera, deviceOrientation: UIDeviceOrientation) {
        print("did change device orientation")
    }
    
    func simpleCameraCaptureScreenOutput(_ camera: SimpleCamera, capturedScreen: CIImage) {
        let capturedImage = capturedScreen.renderUIImage(camera.ciContext)
        UIImageWriteToSavedPhotosAlbum(capturedImage, nil, nil, nil)
    }
    
    func simpleCameraDidCapturePhoto(_ camera: SimpleCamera, photo: Data?) {
        guard let photo = photo else {
            return
        }
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let assetCreationRequest = PHAssetCreationRequest.forAsset()
                assetCreationRequest.addResource(with: .photo, data: photo, options: nil)
            }
        } catch  {
            print("Error! : \(error.localizedDescription))")
        }
        
    }
    
    func simpleCameraCountDownTimer(_ camera: SimpleCamera, _ remainingTime: TimeInterval) {
        print(remainingTime)
    }
}

