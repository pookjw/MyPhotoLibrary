//
//  CollectionViewDataSourceResolver.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import UIKit

@MainActor
final class CollectionViewDataSourceResolver: NSObject, UICollectionViewDataSource {
    typealias NumberOfSectionsResolver = @Sendable @MainActor (UICollectionView) -> Int
    typealias NumberOfItemsInSectionResolver = @Sendable @MainActor (_ collectionView: UICollectionView, _ section: Int) -> Int
    typealias CellForItemAtResolver = @Sendable @MainActor (_ collectionView: UICollectionView, _ indexPath: IndexPath) -> UICollectionViewCell
    typealias ViewForSupplementaryElementOfKindAtResolver = @Sendable @MainActor (_ collectionView: UICollectionView, _ kind: String, _ indexPath: IndexPath) -> UICollectionReusableView
    
    private let numberOfSectionsResolver: NumberOfSectionsResolver
    private let numberOfItemsInSectionResolver: NumberOfItemsInSectionResolver
    private let cellForItemAtResolver: CellForItemAtResolver
    private let viewForSupplementaryElementOfKindAtResolver: ViewForSupplementaryElementOfKindAtResolver
    
    init(
        numberOfSectionsResolver: @escaping NumberOfSectionsResolver,
        numberOfItemsInSectionResolver: @escaping NumberOfItemsInSectionResolver,
        cellForItemAtResolver: @escaping CellForItemAtResolver,
        viewForSupplementaryElementOfKindAtResolver: @escaping ViewForSupplementaryElementOfKindAtResolver
    ) {
        self.numberOfSectionsResolver = numberOfSectionsResolver
        self.numberOfItemsInSectionResolver = numberOfItemsInSectionResolver
        self.cellForItemAtResolver = cellForItemAtResolver
        self.viewForSupplementaryElementOfKindAtResolver = viewForSupplementaryElementOfKindAtResolver
        super.init()
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        numberOfSectionsResolver(collectionView)
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        numberOfItemsInSectionResolver(collectionView, section)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        cellForItemAtResolver(collectionView, indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        viewForSupplementaryElementOfKindAtResolver(collectionView, kind, indexPath)
    }
}
