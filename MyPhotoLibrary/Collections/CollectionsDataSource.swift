//
//  CollectionsDataSource.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import UIKit
import Photos

actor CollectionsDataSource {
    typealias CellProvider = @Sendable @MainActor ((collectionView: UICollectionView, indexPath: IndexPath, fetchResult: PHFetchResult<PHAssetCollection>)) -> UICollectionViewCell
    
    private let cellProvider: CellProvider
    
    @MainActor private weak var collectionView: UICollectionView?
    @MainActor private var fetchResult: PHFetchResult<PHAssetCollection>?
    
    @MainActor
    init(
        collectionView: UICollectionView,
        cellProvider: @escaping CellProvider
    ) {
        self.collectionView = collectionView
        self.cellProvider = cellProvider
    }
}

fileprivate actor CollectionsPhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    typealias PhotoLibraryDidChangeResolver = @Sendable (PHChange) -> Void
    
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
