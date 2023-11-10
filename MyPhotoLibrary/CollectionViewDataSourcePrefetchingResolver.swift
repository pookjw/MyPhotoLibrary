//
//  CollectionViewDataSourcePrefetchingResolver.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 11/10/23.
//

import UIKit

@MainActor
final class CollectionViewDataSourcePrefetchingResolver: NSObject, UICollectionViewDataSourcePrefetching {
    typealias PrefetchItemsAtResolver = @MainActor (_ collectionView: UICollectionView, _ indexPaths: [IndexPath]) -> Void
    typealias CancelPrefetchingForItemsAtResolver = @MainActor (_ collectionView: UICollectionView, _ indexPaths: [IndexPath]) -> Void
    
    private let prefetchItemsAtResolver: PrefetchItemsAtResolver
    private let cancelPrefetchingForItemsAtResolver: CancelPrefetchingForItemsAtResolver
    
    init(
        prefetchItemsAtResolver: @escaping PrefetchItemsAtResolver,
        cancelPrefetchingForItemsAtResolver: @escaping CancelPrefetchingForItemsAtResolver
    ) {
        self.prefetchItemsAtResolver = prefetchItemsAtResolver
        self.cancelPrefetchingForItemsAtResolver = cancelPrefetchingForItemsAtResolver
        super.init()
    }
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetchItemsAtResolver(collectionView, indexPaths)
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        cancelPrefetchingForItemsAtResolver(collectionView, indexPaths)
    }
}
