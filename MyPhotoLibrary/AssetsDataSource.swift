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
                case (.prefetchedWithDegradedImage(let lhsValue), .prefetchedWithDegradedImage(let rhsValue)):
                    lhsValue == rhsValue
                case (.prefetched(let lhsValue), .prefetched(let rhsValue)):
                    lhsValue == rhsValue
                default:
                    false
                }
            }
            
            case prefetching
            case prefetchedWithDegradedImage(UIImage?)
            case prefetched(UIImage?)
            
            var image: UIImage? {
                switch self {
                case .prefetching:
                    nil
                case .prefetchedWithDegradedImage(let image):
                    image
                case .prefetched(let image):
                    image
                }
            }
        }
        
        let requestID: PHImageRequestID
        let requestedImageSize: CGSize
        fileprivate(set) var state: State
    }
    
    typealias CellProvider = @Sendable @MainActor ((collectionView: UICollectionView, indexPath: IndexPath, fetchResult: PHFetchResult<PHAsset>, prefetchedImage: CurrentValueAsyncThrowingSubject<PrefetchedImage>?)) -> UICollectionViewCell
    typealias PrefetchingImageSizeProvider = @Sendable @MainActor ((collectionView: UICollectionView, indexPath: IndexPath)) -> CGSize?
    
    private let imageRequestOptions: PHImageRequestOptions
    private let cellProvider: CellProvider
    private let estimatedImageSizeProvider: PrefetchingImageSizeProvider
    
    @MainActor private weak var collectionView: UICollectionView?
    @MainActor private lazy var collectionViewDataSource: AssetsCollectionViewDataSource = buildCollectionViewDataSource()
    private lazy var photoLibraryChangeObserver: AssetsPhotoLibraryChangeObserver = buildPhotoLibraryChangeObserver()
    @MainActor private var fetchResult: PHFetchResult<PHAsset>?
    @MainActor private var prefetchedImageSubjects: [IndexPath: CurrentValueAsyncThrowingSubject<PrefetchedImage>] = .init()
    
    private var isPrefetchingEnabled: Bool = true
    
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
        collectionView.prefetchDataSource = collectionViewDataSource
    }
    
    deinit {
        memoryWarningTask?.cancel()
        
        Task {
            for prefetchedImage in await prefetchedImageSubjects.values {
                guard let requestID: PHImageRequestID = await prefetchedImage.value?.requestID else {
                    continue
                }
                
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
    
    func load(using collection: PHAssetCollection?) async throws {
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
        
        let fetchResult: PHFetchResult<PHAsset>
        if let collection: PHAssetCollection {
            fetchResult = PHAsset.fetchAssets(in: collection, options: fetchOptions)
        } else {
            fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        }
        
        await MainActor.run {
            self.fetchResult = fetchResult
            self.collectionView?.reloadData()
        }
    }
    
    @MainActor
    private func buildCollectionViewDataSource() -> AssetsCollectionViewDataSource {
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
            prefetchItemsAtResolver: { [weak self] collectionView, indexPaths in
                Task {
                    await self?.prefetchItems(for: indexPaths)
                }
            },
            cancelPrefetchingForItemsAtResolver: { [weak self] collectionView, indexPaths in
                Task {
                    await self?.cancelPrefetching(for: indexPaths)
                }
            }
        )
    }
    
    private func buildPhotoLibraryChangeObserver() -> AssetsPhotoLibraryChangeObserver {
        .init { [weak self] changeInstance in
            Task { [weak self] in
                await self?.photoLibraryDidChange(changeInstance)
            }
        }
    }
    
    private func prefetchItems(for indexPaths: [IndexPath]) async {
        guard let collectionView: UICollectionView = await collectionView else { return }
        
        for indexPath in indexPaths {
            guard isPrefetchingEnabled else { return }
            
            if let requestID: PHImageRequestID = await MainActor.run(body: { self.prefetchedImageSubjects })[indexPath]?.value?.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
                await MainActor.run {
                    _ = self.prefetchedImageSubjects.removeValue(forKey: indexPath)
                }
            }
            
            guard 
                let estimatedSize: CGSize = await estimatedImageSizeProvider((collectionView, indexPath)),
                let phAsset: PHAsset = await fetchResult?.object(at: indexPath.item)
            else {
                continue
            }
            
            let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<PrefetchedImage> = .init()
            
            let requestID: PHImageRequestID = PHImageManager
                .default()
                .requestImage(
                    for: phAsset,
                    targetSize: estimatedSize,
                    contentMode: .aspectFill,
                    options: imageRequestOptions
                ) { [weak self] image, userInfo in
                    guard !(userInfo?[PHImageCancelledKey] as? Bool ?? false) else {
                        Task { [weak self] in
                            await MainActor.run { [weak self] in
                                _ = self?.prefetchedImageSubjects.removeValue(forKey: indexPath)
                            }
                            await prefetchedImageSubject.yield(with: .failure(CancellationError()))
                        }
                        return
                    }
                    
                    if let error: NSError = userInfo?[PHImageErrorKey] as? NSError {
                        Task { [weak self] in
                            await MainActor.run { [weak self] in
                                _ = self?.prefetchedImageSubjects.removeValue(forKey: indexPath)
                            }
                            await prefetchedImageSubject.yield(with: .failure(error))
                        }
                        return
                    }
                    
                    let isDegraded: Bool = userInfo?[PHImageResultIsDegradedKey] as? Bool ?? false
                    
                    Task { [weak self] in
                        guard var prefetchedImage: PrefetchedImage = await prefetchedImageSubject.value else {
                            await MainActor.run { [weak self] in
                                _ = self?.prefetchedImageSubjects.removeValue(forKey: indexPath)
                            }
                            return
                        }
                        
                        let preparedImage: UIImage? = image?.preparingForDisplay()
                        
                        let state: PrefetchedImage.State
                        if isDegraded {
                            state = .prefetchedWithDegradedImage(preparedImage)
                        } else {
                            state = .prefetched(preparedImage)
                        }
                        
                        prefetchedImage.state = state
                        
                        await MainActor.run { [weak self] in
                            _ = self?.prefetchedImageSubjects.removeValue(forKey: indexPath)
                        }
                        await prefetchedImageSubject.yield(prefetchedImage)
                    }
                }
            
            await MainActor.run { [weak self] in
                self?.prefetchedImageSubjects[indexPath] = prefetchedImageSubject
            }
            await prefetchedImageSubject.yield(.init(requestID: requestID, requestedImageSize: estimatedSize, state: .prefetching))
        }
    }
    
    private func cancelPrefetching(for indexPaths: [IndexPath]) async {
        for indexPath in indexPaths {
            if let requestID: PHImageRequestID = await MainActor.run(body: { self.prefetchedImageSubjects })[indexPath]?.value?.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
            
            await MainActor.run {
                _ = self.prefetchedImageSubjects.removeValue(forKey: indexPath)
            }
        }
    }
    
    @MainActor
    private func cellForItem(collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<PrefetchedImage>? = prefetchedImageSubjects[indexPath]
        
        return cellProvider((collectionView, indexPath, fetchResult!, prefetchedImageSubject))
    }
    
    private func didReceiveMemoryWarningNotification(_ notification: Notification) {
        isPrefetchingEnabled = false
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
        let removedIndexPaths: [IndexPath]? = changeDetails.removedIndexes?.map { .init(item: $0, section: .zero) }
        let insertedIndexPaths: [IndexPath]? = changeDetails.insertedIndexes?.map { .init(item: $0, section: .zero) }
        let changedIndexPaths: [IndexPath]? = changeDetails.changedIndexes?.map { .init(item: $0, section: .zero) }
        
        await MainActor.run {
            self.fetchResult = fetchResultAfterChanges
            
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
            }
        }
    }
}

@MainActor
fileprivate final class AssetsCollectionViewDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDataSourcePrefetching {
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

fileprivate actor AssetsPhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
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
