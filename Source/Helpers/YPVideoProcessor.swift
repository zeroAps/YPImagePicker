//
//  YPVideoProcessor.swift
//  YPImagePicker
//
//  Created by Nik Kov on 13.09.2018.
//  Copyright © 2018 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation

/*
 This class contains all support and helper methods to process the videos
 */
class YPVideoProcessor {

    /// Creates an output path and removes the file in temp folder if existing
    ///
    /// - Parameters:
    ///   - temporaryFolder: Save to the temporary folder or somewhere else like documents folder
    ///   - suffix: the file name wothout extension
    static func makeVideoPathURL(temporaryFolder: Bool, fileName: String) -> URL {
        var outputURL: URL
        
        if temporaryFolder {
            let outputPath = "\(NSTemporaryDirectory())\(fileName).\(YPConfig.video.fileType.fileExtension)"
            outputURL = URL(fileURLWithPath: outputPath)
        } else {
            guard let documentsURL = FileManager
                .default
                .urls(for: .documentDirectory,
                      in: .userDomainMask).first else {
                        print("YPVideoProcessor -> Can't get the documents directory URL")
                return URL(fileURLWithPath: "Error")
            }
            outputURL = documentsURL.appendingPathComponent("\(fileName).\(YPConfig.video.fileType.fileExtension)")
        }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputURL.path) {
            do {
                try fileManager.removeItem(atPath: outputURL.path)
            } catch {
                print("YPVideoProcessor -> Can't remove the file for some reason.")
            }
        }
        
        return outputURL
    }
    
    /*
     Crops the video to square by video height from the top of the video.
     */
    static func cropToSquare(filePath: URL, completion: @escaping (_ outputURL : URL?) -> ()) {
        
        var exportProgressBarTimer = Timer()
        
        // output file
        let outputPath = makeVideoPathURL(temporaryFolder: true, fileName: "squaredVideoFromCamera")
        
        // input file
        let asset = AVAsset.init(url: filePath)
        
        // Prevent crash if tracks is empty
        if asset.tracks.isEmpty {
            return
        }
        
        let composition:AVMutableComposition = AVMutableComposition();
        let compositionVideoTrack:AVMutableCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID:0)!
        
        let timeRange:CMTimeRange = CMTimeRangeMake(start: CMTime.zero, duration: asset.duration);
        let videoTrack:AVAssetTrack = asset.tracks(withMediaType: .video)[0]
        try? compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: CMTime.zero)
        
        let instruction:AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction();
        instruction.timeRange = timeRange;
        
        let layerInstruction:AVMutableVideoCompositionLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack);
        
        let videoSize:CGSize = getVideoSize(videoTrack: videoTrack);
        let transform : CGAffineTransform = videoTrack.preferredTransform;
        
        layerInstruction.setTransform(transform, at: CMTime.zero);
        instruction.layerInstructions = [layerInstruction];
        
        let videoComposition:AVMutableVideoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
        videoComposition.renderSize = videoSize
        
        // exporter
        let exporter = AVAssetExportSession.init(asset: asset, presetName: YPConfig.video.compression)
        exporter?.videoComposition = videoComposition
        exporter?.outputURL = outputPath
        exporter?.shouldOptimizeForNetworkUse = true
        exporter?.outputFileType = YPConfig.video.fileType
        
        if #available(iOS 10.0, *) {
            exportProgressBarTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            let progress = Float((exporter?.progress)!)
            if (progress < 0.99) {
               NotificationCenter.default.post(name: Notification.Name("ProgressBarPercentage"), object: Float(progress))
            } else {
                exportProgressBarTimer.invalidate()
            }
          }
        }

        exporter?.exportAsynchronously {
            if exporter?.status == .completed {
                DispatchQueue.main.async(execute: {
                    completion(outputPath)
                })
                return
            } else if exporter?.status == .failed {
                print("YPVideoProcessor -> Export of the video failed. Reason: \(String(describing: exporter?.error))")
            }
            completion(nil)
            return
        }
    }
    
    class func getVideoSize(videoTrack:AVAssetTrack) -> CGSize {
        var videoSize:CGSize = videoTrack.naturalSize;
        let transform:CGAffineTransform = videoTrack.preferredTransform;
        if (transform.a == 0 && transform.d == 0 && (transform.b == 1.0 || transform.b == -1.0) && (transform.c == 1.0 || transform.c == -1.0)) {
            videoSize = CGSize(width: videoSize.height, height: videoSize.width);
        }
        return videoSize;
    }
}
