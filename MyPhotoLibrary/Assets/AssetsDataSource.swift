//
//  AssetsDataSource.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/11/23.
//

import UIKit
import Photos

actor AssetsDataSource {
    struct PrefetchedImage: Sendable, Equatable {
        enum State: Sendable, Equatable {
            static func == (lhs: AssetsDataSource.PrefetchedImage.State, rhs: AssetsDataSource.PrefetchedImage.State) -> Bool {
                switch (lhs, rhs) {
                case (.prefetching, .prefetching):
                    true
                case (.prefetchedWithDegradedImage(let lhs_1, let lhs_2), .prefetchedWithDegradedImage(let rhs_1, let rhs_2)):
                    lhs_1 == rhs_1 && lhs_2 == rhs_2
                case (.prefetched(let lhs_1, let lhs_2), .prefetched(let rhs_1, let rhs_2)):
                    lhs_1 == rhs_1 && lhs_2 == rhs_2
                default:
                    false
                }
            }
            
            case preparing
            case prefetching(PHImageRequestID)
            case prefetchedWithDegradedImage(PHImageRequestID, UIImage?)
            case prefetched(PHImageRequestID, UIImage?)
            
            var image: UIImage? {
                switch self {
                case .preparing, .prefetching:
                    nil
                case .prefetchedWithDegradedImage(_, let image):
                    image
                case .prefetched(_, let image):
                    image
                }
            }
            
            fileprivate var requestID: PHImageRequestID? {
                switch self {
                case .preparing:
                    nil
                case .prefetching(let requestID):
                    requestID
                case .prefetchedWithDegradedImage(let requestID, _):
                    requestID
                case .prefetched(let requestID, _):
                    requestID
                }
            }
        }
        
        let requestedImageSize: CGSize
        fileprivate(set) var state: State
    }
    
    typealias CellProvider = @Sendable @MainActor ((collectionView: UICollectionView, indexPath: IndexPath, fetchResult: PHFetchResult<PHAsset>, prefetchedImage: CurrentValueAsyncThrowingSubject<PrefetchedImage>?)) -> UICollectionViewCell
    typealias PrefetchingImageSizeProvider = @Sendable @MainActor ((collectionView: UICollectionView, indexPath: IndexPath)) -> CGSize?
    
    private let imageRequestOptions: PHImageRequestOptions
    private let cellProvider: CellProvider
    private let estimatedImageSizeProvider: PrefetchingImageSizeProvider
    
    @MainActor private weak var collectionView: UICollectionView?
    @MainActor private lazy var collectionViewDataSource: CollectionViewDataSourceResolver = buildCollectionViewDataSource()
    @MainActor private lazy var collectionViewDataSourcePrefetchingResolver: CollectionViewDataSourcePrefetchingResolver = buildCollectionViewDataSourcePrefetchingResolver()
    private lazy var photoLibraryChangeObserver: PhotoLibraryChangeObserver = buildPhotoLibraryChangeObserver()
    @MainActor private var fetchResult: PHFetchResult<PHAsset>?
    @MainActor private var prefetchedImageSubjects: [IndexPath: CurrentValueAsyncThrowingSubject<PrefetchedImage>] = .init()
    
    @MainActor private var isPrefetchingEnabled: Bool = true
    
    private var memoryWarningTask: Task<Void, Never>? {
        willSet {
            memoryWarningTask?.cancel()
        }
    }
    
    @MainActor
    init(
        collectionView: UICollectionView,
        imageRequestOptions: PHImageRequestOptions,
        cellProvider: @escaping CellProvider,
        estimatedImageSizeProvider: @escaping PrefetchingImageSizeProvider
    ) {
        assert(collectionView.dataSource == nil, "-[UICollectionView dataSource] must be nil.")
        assert(collectionView.prefetchDataSource == nil, "-[UICollectionView prefetchDataSource] must be nil.")
        
        self.collectionView = collectionView
        self.imageRequestOptions = imageRequestOptions
        self.cellProvider = cellProvider
        self.estimatedImageSizeProvider = estimatedImageSizeProvider
        
        collectionView.dataSource = collectionViewDataSource
        collectionView.prefetchDataSource = collectionViewDataSourcePrefetchingResolver
    }
    
    deinit {
        memoryWarningTask?.cancel()
        
        let prefetchedImageSubjects: [IndexPath: CurrentValueAsyncThrowingSubject<PrefetchedImage>] = prefetchedImageSubjects
        
        Task {
            for prefetchedImage in prefetchedImageSubjects.values {
                guard let requestID: PHImageRequestID = await prefetchedImage.value?.state.requestID else {
                    continue
                }
                
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
    
    func load(using collection: PHAssetCollection?) async {
        if memoryWarningTask == nil {
            memoryWarningTask = .init { [weak self] in
                for await notification in await NotificationCenter.default.notifications(named: UIApplication.didReceiveMemoryWarningNotification) {
                    await self?.didReceiveMemoryWarningNotification(notification)
                    break
                }
            }
        }
        
        _ = photoLibraryChangeObserver
        
        //
        
        let fetchOptions: PHFetchOptions = .init()
        fetchOptions.sortDescriptors = [
            .init(.init(\PHAsset.creationDate, order: .reverse))
        ]
        fetchOptions.wantsIncrementalChangeDetails = true
        
        //
        
        let _collection: PHAssetCollection?
        if let collection: PHAssetCollection {
            _collection = collection
        } else {
            let collectionsFetchOptions: PHFetchOptions = .init()
            collectionsFetchOptions.fetchLimit = 1
            
            let collectionsFetchResult: PHFetchResult<PHAssetCollection> = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: collectionsFetchOptions)
            _collection = collectionsFetchResult.firstObject
        }
        
        let fetchResult: PHFetchResult<PHAsset>
        if let _collection: PHAssetCollection {
            fetchResult = PHAsset.fetchAssets(in: _collection, options: fetchOptions)
        } else {
            fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        await MainActor.run {
            self.fetchResult = fetchResult
            self.collectionView?.reloadData()
        }
    }
    
    @MainActor
    private func buildCollectionViewDataSource() -> CollectionViewDataSourceResolver {
        .init(
            numberOfSectionsResolver: { collectionView in
                return 1
            },
            numberOfItemsInSectionResolver: { [weak self] collectionView, section in
                return self?.fetchResult?.count ?? .zero
            },
            cellForItemAtResolver: { [weak self] collectionView, indexPath in
                return self?.cellForItem(collectionView: collectionView, at: indexPath) ?? .init()
            },
            viewForSupplementaryElementOfKindAtResolver: { _, _, _ in
                fatalError()
            }
        )
    }
    
    @MainActor
    private func buildCollectionViewDataSourcePrefetchingResolver() -> CollectionViewDataSourcePrefetchingResolver {
        .init(
            prefetchItemsAtResolver: { [weak self] collectionView, indexPaths in
                guard
                    let self,
                    self.isPrefetchingEnabled
                else {
                    return
                }
                
                indexPaths
                    .forEach { indexPath in
                        guard let estimatedSize: CGSize = self.estimatedImageSizeProvider((collectionView, indexPath)) else {
                            return
                        }
                        
                        if let requestID: PHImageRequestID = self.prefetchedImageSubjects[indexPath]?.value?.state.requestID {
                            PHImageManager.default().cancelImageRequest(requestID)
                        }
                        
                        let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<PrefetchedImage> = .init(value: .init(requestedImageSize: estimatedSize, state: .preparing))
                        prefetchedImageSubject.setFinishHandler { [weak self] in
                            self?.prefetchedImageSubjects.removeValue(forKey: indexPath)
                        }
                        
                        self.prefetchedImageSubjects[indexPath] = prefetchedImageSubject
                    }
                
                Task {
                    await self.prefetchItems(for: indexPaths)
                }
            },
            cancelPrefetchingForItemsAtResolver: { [weak self] collectionView, indexPaths in
                Task {
                    await self?.cancelPrefetching(for: indexPaths)
                }
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
    
    private func prefetchItems(for indexPaths: [IndexPath]) async {
        for indexPath in indexPaths {
            guard let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<PrefetchedImage> = await prefetchedImageSubjects[indexPath] else {
                continue
            }
            
            guard let prefetchedImage: PrefetchedImage = await prefetchedImageSubject.value else {
                fatalError()
            }
            
            if let requestID: PHImageRequestID = prefetchedImage.state.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
                await MainActor.run {
                    _ = self.prefetchedImageSubjects.removeValue(forKey: indexPath)
                }
            }
            
            guard let phAsset: PHAsset = await fetchResult?.ff_PHAsset(at: indexPath.item) else {
                continue
            }
            
            await prefetchedImageSubject.setFinishHandler { [weak self] in
                if let requestID: PHImageRequestID = prefetchedImageSubject.value?.state.requestID {
                    PHImageManager.default().cancelImageRequest(requestID)
                }
                
                self?.prefetchedImageSubjects.removeValue(forKey: indexPath)
            }
            
            let estimatedSize: CGSize = prefetchedImage.requestedImageSize
            
            guard await !prefetchedImageSubject.isFinished else {
                await prefetchedImageSubject.finish()
                continue
            }
            
            let requestID: PHImageRequestID = PHImageManager
                .default()
                .requestImage(
                    for: phAsset,
                    targetSize: estimatedSize,
                    contentMode: .aspectFill,
                    options: imageRequestOptions
                ) { image, userInfo in
                    guard !(userInfo?[PHImageCancelledKey] as? Bool ?? false) else {
                        Task { @MainActor in
                            guard !prefetchedImageSubject.isFinished else {
                                return
                            }
                            
                            prefetchedImageSubject.yield(with: .failure(CancellationError()))
                            prefetchedImageSubject.finish()
                        }
                        
                        return
                    }
                    
                    if let error: NSError = userInfo?[PHImageErrorKey] as? NSError {
                        Task { @MainActor in
                            guard !prefetchedImageSubject.isFinished else {
                                return
                            }
                            
                            prefetchedImageSubject.yield(with: .failure(error))
                            prefetchedImageSubject.finish()
                        }
                        return
                    }
                    
                    let requestID: PHImageRequestID! = userInfo?[PHImageResultRequestIDKey] as? PHImageRequestID
                    let isDegraded: Bool = userInfo?[PHImageResultIsDegradedKey] as? Bool ?? false
                    
                    Task {
                        let preparedImage: UIImage? = await image?.byPreparingForDisplay()
                        
                        let state: PrefetchedImage.State
                        if isDegraded {
                            state = .prefetchedWithDegradedImage(requestID, preparedImage)
                        } else {
                            state = .prefetched(requestID, preparedImage)
                        }
                        
                        await MainActor.run {
                            guard !prefetchedImageSubject.isFinished else {
                                return
                            }
                            
                            prefetchedImageSubject.yield(.init(requestedImageSize: estimatedSize, state: state))
                        }
                    }
                }
            
            await MainActor.run {
                guard !prefetchedImageSubject.isFinished else {
                    return
                }
                
                prefetchedImageSubject.yield(.init(requestedImageSize: estimatedSize, state: .prefetching(requestID)))
            }
        }
    }
    
    private func cancelPrefetching(for indexPaths: [IndexPath]) async {
        for indexPath in indexPaths {
            guard let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage> = await MainActor.run(body: { self.prefetchedImageSubjects })[indexPath] else {
                continue
            }
            
            await prefetchedImageSubject.finish()
            
            if let requestID: PHImageRequestID = await prefetchedImageSubject.value?.state.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
    
    @MainActor
    private func cellForItem(collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<PrefetchedImage>? = prefetchedImageSubjects[indexPath]
        
        return cellProvider((collectionView, indexPath, fetchResult!, prefetchedImageSubject))
    }
    
    private func didReceiveMemoryWarningNotification(_ notification: Notification) async {
        await MainActor.run {
            isPrefetchingEnabled = false
        }
    }
    
    private func photoLibraryDidChange(_ changeInstance: PHChange) async {
        guard 
            let fetchResult: PHFetchResult<PHAsset> = await MainActor.run(body: { self.fetchResult }),
            let changeDetails: PHFetchResultChangeDetails<PHAsset> = changeInstance.changeDetails(for: fetchResult)
        else {
            return
        }
        
        assert(changeDetails.hasIncrementalChanges, "TODO")
        
        let fetchResultAfterChanges: PHFetchResult<PHAsset> = changeDetails.fetchResultAfterChanges
        
        let removedIndexPaths: [IndexPath]? = changeDetails
            .removedIndexes?
            .map { .init(item: $0, section: .zero) }
        
        let insertedIndexPaths: [IndexPath]? = changeDetails
            .insertedIndexes?
            .map { .init(item: $0, section: .zero) }
        
        let changedIndexPaths: [IndexPath]? = changeDetails
            .changedIndexes?
            .map { .init(item: $0, section: .zero) }
        
        guard !(removedIndexPaths?.isEmpty ?? true) || !(insertedIndexPaths?.isEmpty ?? true) || !(changedIndexPaths?.isEmpty ?? true) || changeDetails.hasMoves else {
            return
        } 
        
        await MainActor.run {
            guard let collectionView: UICollectionView else { return }
            
            collectionView.performBatchUpdates {
                if let removedIndexPaths: [IndexPath] {
                    collectionView.deleteItems(at: removedIndexPaths)
                }
                
                if let insertedIndexPaths: [IndexPath] {
                    collectionView.insertItems(at: insertedIndexPaths)
                }
                
                if let changedIndexPaths: [IndexPath] {
                    collectionView.reconfigureItems(at: changedIndexPaths)
                }
                
                changeDetails.enumerateMoves { fromIndex, toIndex in
                    collectionView.moveItem(at: .init(item: fromIndex, section: .zero), to: .init(item: toIndex, section: .zero))
                }
                
                self.fetchResult = fetchResultAfterChanges
            }
        }
    }
}
