//
//  CollectionsViewModel.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import Foundation
import Photos

actor CollectionsViewModel {
    private let collectionsDataSource: CollectionsDataSource
    
    init(collectionsDataSource: CollectionsDataSource) {
        self.collectionsDataSource = collectionsDataSource
    }
    
    func load() async throws {
        await collectionsDataSource.load()
    }
    
    func indexPath(for collection: PHAssetCollection) async -> IndexPath? {
        await collectionsDataSource.indexPath(for: collection)
    }
    
    func collection(at indexPath: IndexPath) async -> PHAssetCollection? {
        await collectionsDataSource.collection(for: indexPath)
    }
}
