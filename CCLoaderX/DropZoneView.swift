//
//  DropZoneView.swift
//  Bitmapper
//
//  Created by Alex on 01-03-15.
//  Copyright (c) 2015 Balancing Rock. All rights reserved.
//
import Cocoa

protocol DropZoneDelegate: NSDraggingDestination {
    /// Redirect of the performDragOperations (required)
    func performDragOperation(_ info: NSDraggingInfo) -> Bool
}

class DropZoneView: NSView {
    
    //MARK: - Instance variables
    
    var dropDelegate: DropZoneDelegate?
    
    /// The array holding the file extensions that are accepted (e.g. ["mp3", "aac"])
    var acceptedFiles: [String] = []
    
    /// The dragOperation that will de returned if an optoinal DropZoneDelegate function has not been implemented
    var defaultDragOperation = NSDragOperation.copy
    
    
    //MARK: - Functions
    
    /// A helper function, to make it easier to register for specific file types. The array should look like ["mp3", "aac", "psd"] etc.
    func registerForFileExtensions(_ extensions: [String]) {
        var types: [String] = []
        
        for ext in extensions {
            types.append("NSTypedFilenamesPboardType:\(ext)")
        }
        
        registerForDraggedTypes([NSPasteboard.PasteboardType("NSFilenamesPboardType")])
        acceptedFiles = extensions
    }
    
    /// Returns the file urls from the given DraggingInfo
    class func fileUrlsFromDraggingInfo(_ info: NSDraggingInfo) -> [URL]? {
        let pboard = info.draggingPasteboard()
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [NSURL],
                urls.count > 0 {
            var realUrls = [URL]()
            for url in urls {
                realUrls.append(url.filePathURL!) // use filePathURL to avoid file:// file id's
            }
            
            return realUrls
        }
        
        return nil
    }
    
    /// Returns whether the dragginginfo has any valid files
    private func hasValidFiles(_ info: NSDraggingInfo) -> Bool {
        var hasValidFiles = false
        //let pboard = info.draggingPasteboard()
        
        let urls = DropZoneView.fileUrlsFromDraggingInfo(info)
        if urls == nil { return false }
        
        for url in urls! {
            if acceptedFiles.contains(url.pathExtension) { hasValidFiles = true }
        }
        
        return hasValidFiles
    }
    
    
    //MARK: - Dragging functions
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !hasValidFiles(sender) {
            return []
        } else {
            return defaultDragOperation
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if !hasValidFiles(sender) {
            return []
        } else {
            return defaultDragOperation
        }
    }
    
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let del = dropDelegate {
            return del.performDragOperation(sender)
        }
        
        return true
    }
}
