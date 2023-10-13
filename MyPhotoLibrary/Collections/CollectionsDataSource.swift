//
//  CollectionsDataSource.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import UIKit
import Photos

actor CollectionsDataSource {
    typealias CellProvider = @Sendable @MainActor ((collectionView: UICollectionView, indexPath: IndexPath, collection: PHAssetCollection)) -> UICollectionViewCell
    
    private let cellProvider: CellProvider
    
    @MainActor private weak var collectionView: UICollectionView?
    @MainActor private lazy var collectionViewDataSource: CollectionViewDataSourceResolver = buildCollectionViewDataSource()
    private lazy var photoLibraryChangeObserver: PhotoLibraryChangeObserver = buildPhotoLibraryChangeObserver()
    
    @MainActor private var smartCollectionsFetchResult: PHFetchResult<PHAssetCollection>?
    @MainActor private var collectionsFetchResult: PHFetchResult<PHAssetCollection>?
    
    @MainActor
    init(
        collectionView: UICollectionView,
        cellProvider: @escaping CellProvider
    ) {
        assert(collectionView.dataSource == nil, "-[UICollectionView dataSource] must be nil.")
        assert(collectionView.prefetchDataSource == nil, "-[UICollectionView prefetchDataSource] must be nil.")
        
        self.collectionView = collectionView
        self.cellProvider = cellProvider
        
        collectionView.dataSource = collectionViewDataSource
        collectionView.prefetchDataSource = collectionViewDataSource
    }
    
    func load() async {
        _ = photoLibraryChangeObserver
        
        let fetchOptions: PHFetchOptions = .init()
        fetchOptions.sortDescriptors = [.init(.init(\PHAssetCollection.startDate, order: .reverse))]
        fetchOptions.wantsIncrementalChangeDetails = true
        
        let smartCollectionsFetchResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: fetchOptions)
        let collectionsFetchResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
        
        await MainActor.run {
            self.smartCollectionsFetchResult = smartCollectionsFetchResult
            self.collectionsFetchResult = collectionsFetchResult
            self.collectionView?.reloadData()
        }
    }
    
    func collection(for indexPath: IndexPath) async -> PHAssetCollection? {
        guard let fetchResult: PHFetchResult<PHAssetCollection> = await fetchResult(for: indexPath.section) else {
            return nil
        }
        
        return fetchResult.object(at: indexPath.item)
    }
    
    func indexPath(for collection: PHAssetCollection) async -> IndexPath? {
        switch collection.assetCollectionType {
        case .smartAlbum:
            guard 
                let smartCollectionsFetchResult: PHFetchResult<PHAssetCollection> = await smartCollectionsFetchResult,
                let section: Int = await sections(smartCollectionsFetchResult: smartCollectionsFetchResult, collectionsFetchResult: collectionsFetchResult).smartCollectionsSection
            else {
                return nil
            }
            
            let index: Int = smartCollectionsFetchResult.index(of: collection)
            return .init(item: index, section: section)
        case .album:
            guard 
                let collectionsFetchResult: PHFetchResult<PHAssetCollection> = await collectionsFetchResult,
                let section: Int = await sections(smartCollectionsFetchResult: smartCollectionsFetchResult, collectionsFetchResult: collectionsFetchResult).collectionsSection
            else {
                return nil
            }
            
            let index: Int = collectionsFetchResult.index(of: collection)
            return .init(item: index, section: section)
        default:
            return nil
        }
    }
    
    @MainActor
    private func buildCollectionViewDataSource() -> CollectionViewDataSourceResolver {
        .init(
            numberOfSectionsResolver: { [weak self] collectionView in
                return self?.numberOfSections ?? .zero
            },
            numberOfItemsInSectionResolver: { [weak self] collectionView, section in
                return self?.nunberOfItemsInSection(section) ?? .zero
            },
            cellForItemAtResolver: { [weak self] collectionView, indexPath in
                return self?.cellForItem(collectionView: collectionView, at: indexPath) ?? .init()
            },
            prefetchItemsAtResolver: { collectionView, indexPaths in
                
            },
            cancelPrefetchingForItemsAtResolver: { collectionView, indexPaths in
                
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
    
    @MainActor private var numberOfSections: Int {
        let smartCollectionsCount: Int = smartCollectionsFetchResult?.count ?? .zero
        let collectionsCount: Int = collectionsFetchResult?.count ?? .zero
        
        return (smartCollectionsCount > .zero ? 1 : .zero) + (collectionsCount > .zero ? 1 : .zero)
    }
    
    @MainActor private func nunberOfItemsInSection(_ section: Int) -> Int {
        fetchResult(for: section)?.count ?? .zero
    }
    
    @MainActor private func cellForItem(collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        return cellProvider((collectionView, indexPath, fetchResult(for: indexPath.section)!.object(at: indexPath.item)))
    }
    
    private func photoLibraryDidChange(_ changeInstance: PHChange) async {
        let smartCollectionsFetchResult: PHFetchResult<PHAssetCollection>? = await MainActor.run { self.smartCollectionsFetchResult }
        
        let smartCollectionChangeDetails: PHFetchResultChangeDetails<PHAssetCollection>?
        let smartCollectionsFetchResultAfterChanges: PHFetchResult<PHAssetCollection>?
        
        if let smartCollectionsFetchResult: PHFetchResult<PHAssetCollection> {
            smartCollectionChangeDetails = changeInstance.changeDetails(for: smartCollectionsFetchResult)
            smartCollectionsFetchResultAfterChanges = smartCollectionChangeDetails?.fetchResultAfterChanges ?? smartCollectionsFetchResult
        } else {
            smartCollectionChangeDetails = nil
            smartCollectionsFetchResultAfterChanges = smartCollectionsFetchResult
        }
        
        //
        
        let collectionsFetchResult: PHFetchResult<PHAssetCollection>? = await MainActor.run { self.collectionsFetchResult }
        let collectionChangeDetails: PHFetchResultChangeDetails<PHAssetCollection>?
        let collectionsFetchResultAfterChanges: PHFetchResult<PHAssetCollection>?
        
        if let collectionsFetchResult: PHFetchResult<PHAssetCollection> {
            collectionChangeDetails = changeInstance.changeDetails(for: collectionsFetchResult)
            collectionsFetchResultAfterChanges = collectionChangeDetails?.fetchResultAfterChanges ?? collectionsFetchResult
        } else {
            collectionChangeDetails = nil
            collectionsFetchResultAfterChanges = collectionsFetchResult
        }
        
        //
        
        let (oldSmartCollectionsSection, oldCollectionsSection): (Int?, Int?) = sections(smartCollectionsFetchResult: smartCollectionsFetchResult, collectionsFetchResult: collectionsFetchResult)
        let (newSmartCollectionsSection, newCollectionsSection): (Int?, Int?) = sections(smartCollectionsFetchResult: smartCollectionsFetchResultAfterChanges, collectionsFetchResult: collectionsFetchResultAfterChanges)
        
        var deletedSections: IndexSet = .init()
        var insertedSections: IndexSet = .init()
        [(oldSmartCollectionsSection, newSmartCollectionsSection), (oldCollectionsSection, newCollectionsSection)]
            .forEach { oldSection, newSection in
                if let oldSection: Int, newSection == nil {
                    deletedSections.insert(oldSection)
                } else if oldSection == nil, let newSection: Int {
                    insertedSections.insert(newSection)
                }
            }
        
        //
        
        let smartCollectionsRemovedIndexPaths: [IndexPath]?
        let smartCollectionsInsertedIndexPaths: [IndexPath]?
        let smartCollectionsChangedIndexPaths: [IndexPath]?
        
        if 
            let smartCollectionChangeDetails: PHFetchResultChangeDetails<PHAssetCollection>,
            let newSmartCollectionsSection: Int
        {
            smartCollectionsRemovedIndexPaths = smartCollectionChangeDetails
                .removedIndexes?
                .map { .init(item: $0, section: newSmartCollectionsSection) }
            
            smartCollectionsInsertedIndexPaths = smartCollectionChangeDetails
                .insertedIndexes?
                .map { .init(item: $0, section: newSmartCollectionsSection) }
            
            smartCollectionsChangedIndexPaths = smartCollectionChangeDetails
                .changedIndexes?
                .map { .init(item: $0, section: newSmartCollectionsSection) }
        } else {
            smartCollectionsRemovedIndexPaths = nil
            smartCollectionsInsertedIndexPaths = nil
            smartCollectionsChangedIndexPaths = nil
        }
        
        //
        
        let collectionsRemovedIndexPaths: [IndexPath]?
        let collectionsInsertedIndexPaths: [IndexPath]?
        let collectionsChangedIndexPaths: [IndexPath]?
        
        if 
            let collectionChangeDetails: PHFetchResultChangeDetails<PHAssetCollection>,
            let newCollectionsSection: Int
        {
            collectionsRemovedIndexPaths = collectionChangeDetails
                .removedIndexes?
                .map { .init(item: $0, section: newCollectionsSection) }
            
            collectionsInsertedIndexPaths = collectionChangeDetails
                .insertedIndexes?
                .map { .init(item: $0, section: newCollectionsSection) }
            
            collectionsChangedIndexPaths = collectionChangeDetails
                .changedIndexes?
                .map { .init(item: $0, section: newCollectionsSection) }
        } else {
            collectionsRemovedIndexPaths = nil
            collectionsInsertedIndexPaths = nil
            collectionsChangedIndexPaths = nil
        }
        
        //
        
        guard 
            !deletedSections.isEmpty ||
                !insertedSections.isEmpty ||
                !(smartCollectionsRemovedIndexPaths?.isEmpty ?? true) ||
                !(smartCollectionsInsertedIndexPaths?.isEmpty ?? true) ||
                !(smartCollectionsChangedIndexPaths?.isEmpty ?? true) ||
                !(collectionsRemovedIndexPaths?.isEmpty ?? true) ||
                !(collectionsInsertedIndexPaths?.isEmpty ?? true) ||
                !(collectionsChangedIndexPaths?.isEmpty ?? true) 
        else {
            return
        } 
        
        //
        
        await MainActor.run { [deletedSections, insertedSections] in
            self.smartCollectionsFetchResult = smartCollectionsFetchResultAfterChanges
            self.collectionsFetchResult = collectionsFetchResultAfterChanges
            
            guard let collectionView: UICollectionView else { return }
            
            collectionView.performBatchUpdates {
                if !deletedSections.isEmpty {
                    collectionView.deleteSections(deletedSections)
                }              
                
                if !insertedSections.isEmpty {
                    collectionView.insertSections(insertedSections)
                }
                
                if let smartCollectionsRemovedIndexPaths: [IndexPath] {
                    collectionView.deleteItems(at: smartCollectionsRemovedIndexPaths)
                }
                
                if let smartCollectionsInsertedIndexPaths: [IndexPath] {
                    collectionView.insertItems(at: smartCollectionsInsertedIndexPaths)
                }
                
                if let smartCollectionsChangedIndexPaths: [IndexPath] {
                    collectionView.reconfigureItems(at: smartCollectionsChangedIndexPaths)
                }
                
                if let collectionsRemovedIndexPaths: [IndexPath] {
                    collectionView.deleteItems(at: collectionsRemovedIndexPaths)
                }
                
                if let collectionsInsertedIndexPaths: [IndexPath] {
                    collectionView.insertItems(at: collectionsInsertedIndexPaths)
                }
                
                if let collectionsChangedIndexPaths: [IndexPath] {
                    collectionView.reconfigureItems(at: collectionsChangedIndexPaths)
                }
            }
        }
    }
    
    @MainActor
    private func fetchResult(for section: Int) -> PHFetchResult<PHAssetCollection>? {
        let smartCollectionsCount: Int = smartCollectionsFetchResult?.count ?? .zero
        let collectionsCount: Int = collectionsFetchResult?.count ?? .zero
        
        if smartCollectionsCount > .zero && collectionsCount == .zero {
            switch section {
            case .zero:
                return smartCollectionsFetchResult
            default:
                return nil
            }
        } else if smartCollectionsCount > .zero && collectionsCount > .zero {
            switch section {
            case .zero:
                return smartCollectionsFetchResult
            case 1:
                return collectionsFetchResult
            default:
                return nil
            }
        } else if smartCollectionsCount == .zero && collectionsCount == .zero {
            return nil
        } else if smartCollectionsCount == .zero && collectionsCount > .zero {
            switch section {
            case .zero:
                return collectionsFetchResult
            default:
                return nil
            }
        } else {
            return nil
        }
    }
    
    private nonisolated func sections(smartCollectionsFetchResult: PHFetchResult<PHAssetCollection>?, collectionsFetchResult: PHFetchResult<PHAssetCollection>?) -> (smartCollectionsSection: Int?, collectionsSection: Int?) {
        let smartCollectionsCount: Int = smartCollectionsFetchResult?.count ?? .zero
        let collectionsCount: Int = collectionsFetchResult?.count ?? .zero
        
        let smartCollectionsSection: Int?
        let collectionsSection: Int?
        
        if smartCollectionsCount > .zero && collectionsCount == .zero {
            smartCollectionsSection = .zero
            collectionsSection = nil
        } else if smartCollectionsCount > .zero && collectionsCount > .zero {
            smartCollectionsSection = .zero
            collectionsSection = 1
        } else if smartCollectionsCount == .zero && collectionsCount > .zero {
            smartCollectionsSection = nil
            collectionsSection = .zero
        } else {
            smartCollectionsSection = nil
            collectionsSection = nil
        }
        
        return (smartCollectionsSection, collectionsSection)
    }
}
