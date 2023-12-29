//
//  CollectionsDataSource.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import UIKit
import Photos

actor CollectionsDataSource {
    typealias CellProvider = @Sendable @MainActor (_ collectionView: UICollectionView, _ indexPath: IndexPath, _ fetchResult: PHFetchResult<PHAssetCollection>) -> UICollectionViewCell
    typealias SupplementaryViewProvider = @Sendable @MainActor (_ collectionView: UICollectionView, _ elementKind: String, _ indexPath: IndexPath) -> UICollectionReusableView
    
    private let cellProvider: CellProvider
    private let supplementaryViewProvider: SupplementaryViewProvider
    @MainActor private weak var collectionView: UICollectionView?
    @MainActor private lazy var collectionViewDataSourceResolver: CollectionViewDataSourceResolver = buildCollectionViewDataSourceResolver()
    private lazy var photoLibraryChangeObserver: PhotoLibraryChangeObserver = buildPhotoLibraryChangeObserver()
    
    @MainActor private var numberOfSections: Int = .zero
    @MainActor private var numberOfItemsInSection: [Int: Int] = .init()
    @MainActor private var fetchResults: [PHAssetCollectionType: PHFetchResult<PHAssetCollection>] = .init()
    @MainActor private var collectionTypesForSection: [Int: PHAssetCollectionType] = .init()
    
    @MainActor
    init(
        collectionView: UICollectionView,
        cellProvider: @escaping CellProvider,
        supplementaryViewProvider: @escaping SupplementaryViewProvider
    ) {
        assert(collectionView.dataSource == nil, "-[UICollectionView dataSource] must be nil")
        
        self.collectionView = collectionView
        self.cellProvider = cellProvider
        self.supplementaryViewProvider = supplementaryViewProvider
        
        collectionView.dataSource = collectionViewDataSourceResolver
    }
    
    func load() async {
        _ = photoLibraryChangeObserver
        
        let fetchOptions: PHFetchOptions = .init()
        fetchOptions.wantsIncrementalChangeDetails = true
        
        let smartCollectionsFetchResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: fetchOptions)
        let collectionsFetchResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        guard !Task.isCancelled else {
            return
        }
        
        let fetchResults: [PHAssetCollectionType: PHFetchResult<PHAssetCollection>] = [
            .smartAlbum: smartCollectionsFetchResult,
            .album: collectionsFetchResult
        ]
        
        let (numberOfSections, numberOfItemsInSection, collectionTypesForSection): (Int, [Int: Int], [Int: PHAssetCollectionType]) = dataSourceProperties(from: fetchResults)
        
        await MainActor.run {
            self.numberOfSections = numberOfSections
            self.numberOfItemsInSection = numberOfItemsInSection
            self.fetchResults = fetchResults
            self.collectionTypesForSection = collectionTypesForSection
            collectionView?.reloadData()
        }
    }
    
    func phAssetCollection(from indexPath: IndexPath) async -> PHAssetCollection? {
        let (collectionTypesForSection, fetchResults): ([Int: PHAssetCollectionType], [PHAssetCollectionType: PHFetchResult<PHAssetCollection>]) = await MainActor.run { (self.collectionTypesForSection, self.fetchResults) }
        
        guard
            let collectionType: PHAssetCollectionType = collectionTypesForSection[indexPath.section],
            let fetchResult: PHFetchResult<PHAssetCollection> = fetchResults[collectionType],
            indexPath.item < fetchResult.count
        else {
            return nil
        }
        
        return fetchResult.object(at: indexPath.item)
    }
    
    func indexPath(from phAssetCollection: PHAssetCollection) async -> IndexPath? {
        let (collectionTypesForSection, fetchResults): ([Int: PHAssetCollectionType], [PHAssetCollectionType: PHFetchResult<PHAssetCollection>]) = await MainActor.run { (self.collectionTypesForSection, self.fetchResults) }
        
        for (collectionType, fetchResult) in fetchResults {
            var item: Int?
            
            fetchResult.enumerateObjects { _phAssetCollection, index, stopPtr in
                if _phAssetCollection == phAssetCollection {
                    item = index
                    stopPtr.pointee = .init(true)
                }
            }
            
            if
                let item: Int,
                let secton: Int = collectionTypesForSection.first(where: { $0.value == collectionType })?.key
            {
                return .init(item: item, section: secton)
            }
        }
        
        return nil
    }
    
    @MainActor
    private func buildCollectionViewDataSourceResolver() -> CollectionViewDataSourceResolver {
        .init(
            numberOfSectionsResolver: { [weak self] _ in
                return self?.numberOfSections ?? .zero
            },
            numberOfItemsInSectionResolver: { [weak self] (_, section) in
                return self?.numberOfItemsInSection[section] ?? .zero
            },
            cellForItemAtResolver: { [weak self] (collectionView, indexPath) in
                guard
                    let self,
                    let collectionType: PHAssetCollectionType = self.collectionTypesForSection[indexPath.section],
                    let fetchResult: PHFetchResult<PHAssetCollection> = self.fetchResults[collectionType]
                else {
                    fatalError()
                }
                
                return self.cellProvider(collectionView, indexPath, fetchResult)
            },
            viewForSupplementaryElementOfKindAtResolver: { [supplementaryViewProvider] (collectionView, kind, indexPath) in
                supplementaryViewProvider(collectionView, kind, indexPath)
            }
        )
    }
    
    private func buildPhotoLibraryChangeObserver() -> PhotoLibraryChangeObserver {
        .init { [weak self] changeInstance in
            Task { [weak self] in
                await self?.photoLibraryDidChange(changeInstance)
            }
        }
    }
    
    private nonisolated func dataSourceProperties(from fetchResults: [PHAssetCollectionType: PHFetchResult<PHAssetCollection>]) -> (numberOfSections: Int, numberOfItemsInSection: [Int: Int], collectionTypesForSection: [Int: PHAssetCollectionType]) {
        var numberOfItemsInSection: [Int: Int] = .init()
        var collectionTypesForSection: [Int: PHAssetCollectionType] = .init()
        
        for collectionType in [PHAssetCollectionType.smartAlbum, PHAssetCollectionType.album] {
            guard let fetchResult: PHFetchResult<PHAssetCollection> = fetchResults[collectionType] else {
                continue
            }
            
            let count = fetchResult.count
            guard count > .zero else {
                continue
            }
            
            let section: Int = numberOfItemsInSection.count
            
            numberOfItemsInSection[section] = count
            collectionTypesForSection[section] = collectionType
        }
        
        let numberOfSections = numberOfItemsInSection.count
        
        return (numberOfSections, numberOfItemsInSection, collectionTypesForSection)
    }
    
    private func photoLibraryDidChange(_ changeInstance: PHChange) async {
        var fetchResults: [PHAssetCollectionType: PHFetchResult<PHAssetCollection>] = await MainActor.run { self.fetchResults }
        let collectionTypesForSection: [Int: PHAssetCollectionType] = await MainActor.run { self.collectionTypesForSection }
        
        //
        
        var removedIndexPaths: [IndexPath] = .init()
        var insertedIndexPaths: [IndexPath] = .init()
        var changedIndexPaths: [IndexPath] = .init()
        var movedIndexPaths: [(old: IndexPath, new: IndexPath)] = .init()
        
        for collectionType in [PHAssetCollectionType.smartAlbum, PHAssetCollectionType.album] {
            guard
                let section: Int = collectionTypesForSection.first(where: { $0.value == collectionType })?.key,
                let oldFetchResult: PHFetchResult<PHAssetCollection> = fetchResults[collectionType],
                let changeDetails: PHFetchResultChangeDetails<PHAssetCollection> = changeInstance.changeDetails(for: oldFetchResult),
                changeDetails.hasIncrementalChanges
            else {
                continue
            }
            
            let newFetchResult: PHFetchResult<PHAssetCollection> = changeDetails.fetchResultAfterChanges
            
            if let removedIndexes: IndexSet = changeDetails.removedIndexes {
                let _removedIndexPaths: [IndexPath] = removedIndexes
                    .map { IndexPath(item: $0, section: section) }
                removedIndexPaths.append(contentsOf: _removedIndexPaths)
            }
            
            if let insertedIndexes: IndexSet = changeDetails.insertedIndexes {
                let _insertedIndexPaths: [IndexPath] = insertedIndexes
                    .map { IndexPath(item: $0, section: section) }
                insertedIndexPaths.append(contentsOf: _insertedIndexPaths)
            }
            
            if let changedIndexes: IndexSet = changeDetails.changedIndexes {
                let _changedIndexPaths: [IndexPath] = changedIndexes
                    .map { IndexPath(item: $0, section: section) }
                changedIndexPaths.append(contentsOf: _changedIndexPaths)
            }
            
            if changeDetails.hasMoves {
                changeDetails.enumerateMoves { old, new in
                    movedIndexPaths.append((.init(item: old, section: section), new: .init(item: new, section: section)))
                }
            }
            
            fetchResults[collectionType] = newFetchResult
        }
        
        //
        
        guard
            !removedIndexPaths.isEmpty ||
                !insertedIndexPaths.isEmpty ||
                !changedIndexPaths.isEmpty ||
                !movedIndexPaths.isEmpty
        else {
            await MainActor.run { [fetchResults] in
                self.fetchResults = fetchResults
            }
            
            return
        }
        
        await MainActor.run { [fetchResults, removedIndexPaths, insertedIndexPaths, changedIndexPaths, movedIndexPaths] in
            guard let collectionView: UICollectionView else {
                self.fetchResults = fetchResults
                return
            }
            
            collectionView.performBatchUpdates {
                let (numberOfSections, numberOfItemsInSection, collectionTypesForSection) = dataSourceProperties(from: fetchResults)
                
                self.numberOfSections = numberOfSections
                self.numberOfItemsInSection = numberOfItemsInSection
                self.fetchResults = fetchResults
                self.collectionTypesForSection = collectionTypesForSection
                
                //
                
                collectionView.deleteItems(at: removedIndexPaths)
                collectionView.insertItems(at: insertedIndexPaths)
                collectionView.reconfigureItems(at: changedIndexPaths)
                
                movedIndexPaths
                    .forEach { (old, new) in
                        collectionView.moveItem(at: old, to: new)
                    }
            }
        }
    }
}
