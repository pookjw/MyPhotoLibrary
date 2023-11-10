//
//  PhotoLibraryChangeObserverResolver.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import Foundation
import Photos

actor PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    typealias PhotoLibraryDidChangeResolver = @Sendable (_ changeInstance: PHChange) -> Void
    
    private let photoLibraryDidChangeResolver: PhotoLibraryDidChangeResolver
    
    init(photoLibraryDidChangeResolver: @escaping PhotoLibraryDidChangeResolver) {
        self.photoLibraryDidChangeResolver = photoLibraryDidChangeResolver
        super.init()
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        photoLibraryDidChangeResolver(changeInstance)
    }
}
