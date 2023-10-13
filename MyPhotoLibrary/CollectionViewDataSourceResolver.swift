//
//  CollectionViewDataSourceResolver.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import UIKit

@MainActor
final class CollectionViewDataSourceResolver: NSObject, UICollectionViewDataSource, UICollectionViewDataSourcePrefetching {
    typealias NumberOfSectionsResolver = @MainActor (UICollectionView) -> Int
    typealias NumberOfItemsInSectionResolver = @MainActor ((collectionView: UICollectionView, section: Int)) -> Int
    typealias CellForItemAtResolver = @MainActor ((collectionView: UICollectionView, indexPath: IndexPath)) -> UICollectionViewCell
    typealias PrefetchItemsAtResolver = @MainActor ((collectionView: UICollectionView, indexPaths: [IndexPath])) -> Void
    typealias CancelPrefetchingForItemsAtResolver = @MainActor ((collectionView: UICollectionView, indexPaths: [IndexPath])) -> Void
    
    private let numberOfSectionsResolver: NumberOfSectionsResolver
    private let numberOfItemsInSectionResolver: NumberOfItemsInSectionResolver
    private let cellForItemAtResolver: CellForItemAtResolver
    private let prefetchItemsAtResolver: PrefetchItemsAtResolver
    private let cancelPrefetchingForItemsAtResolver: CancelPrefetchingForItemsAtResolver
    
    init(
        numberOfSectionsResolver: @escaping NumberOfSectionsResolver,
        numberOfItemsInSectionResolver: @escaping NumberOfItemsInSectionResolver,
        cellForItemAtResolver: @escaping CellForItemAtResolver,
        prefetchItemsAtResolver: @escaping PrefetchItemsAtResolver,
        cancelPrefetchingForItemsAtResolver: @escaping CancelPrefetchingForItemsAtResolver
    ) {
        self.numberOfSectionsResolver = numberOfSectionsResolver
        self.numberOfItemsInSectionResolver = numberOfItemsInSectionResolver
        self.cellForItemAtResolver = cellForItemAtResolver
        self.prefetchItemsAtResolver = prefetchItemsAtResolver
        self.cancelPrefetchingForItemsAtResolver = cancelPrefetchingForItemsAtResolver
        super.init()
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        numberOfSectionsResolver(collectionView)
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        numberOfItemsInSectionResolver((collectionView, section))
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        cellForItemAtResolver((collectionView, indexPath))
    }
    
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        prefetchItemsAtResolver((collectionView, indexPaths))
    }
    
    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        cancelPrefetchingForItemsAtResolver((collectionView, indexPaths))
    }
}
