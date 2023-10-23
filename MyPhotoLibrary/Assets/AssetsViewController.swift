//
//  AssetsViewController.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/11/23.
//

import UIKit
import SwiftUI
import Photos

@MainActor
final class AssetsViewController: UIViewController {
    @ViewLoading private var collectionView: UICollectionView
    @ViewLoading private var viewModel: AssetsViewModel
    @ViewLoading private var collectionsButton: UIButton
    
    private let imageRequestOptions: PHImageRequestOptions = {
        let options: PHImageRequestOptions = .init()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        if #available(iOS 17.0, visionOS 1.0, *) {
            options.allowSecondaryDegradedImage = true
        }
        
        return options
    }()
    
    private var loadingTask: Task<Void, Never>? {
        willSet {
            loadingTask?.cancel()
        }
    }
    private var didChangeSelectedCollection: Task<Void, Never>? {
        willSet {
            didChangeSelectedCollection?.cancel()
        }
    }
    
    deinit {
        loadingTask?.cancel()
        didChangeSelectedCollection?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupViewModel()
        setupCollectionsButton()
        setupAttributes()
        load()
    }
    
    private func setupAttributes() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.titleView = collectionsButton
    }
    
    private func setupCollectionView() {
        let collectionViewLayout: UICollectionViewLayout = buildCollectionViewLayout()
        let collectionView: UICollectionView = .init(frame: view.bounds, collectionViewLayout: collectionViewLayout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        
        view.addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    private func setupCollectionsButton() {
        let collectionsButton: UIButton = .init(primaryAction: .init(handler: { [weak self] _ in
            Task {
                guard let self else { return }
                
                let viewController: CollectionsViewController = .init(selectedCollection: nil)
                
                self.didChangeSelectedCollection = .init { [weak self, subject = viewController.selectedCollectionSubject] in
                    for await selectedCollection in await subject() {
                        try! await self?.select(collection: selectedCollection)
                    }
                }
                
                self.present(viewController, animated: true)
            }
        }))
        
        self.collectionsButton = collectionsButton
    }
    
    private func setupViewModel() {
        let assetsDataSource: AssetsDataSource = buildAssetsDataSource()
        let viewModel: AssetsViewModel = .init(assetsDataSource: assetsDataSource)
        self.viewModel = viewModel
    }
    
    private func load() {
        loadingTask = .init { [weak self] in
            try! await self?.select(collection: nil)
        }
    }
    
    private func buildCollectionViewLayout() -> UICollectionViewLayout {
        let configuration: UICollectionViewCompositionalLayoutConfiguration = .init()
        configuration.scrollDirection = .vertical
        
        return UICollectionViewCompositionalLayout(
            sectionProvider: { sectionIndex, environment in
                let quotient: Int = .init(floorf(Float(environment.container.contentSize.width) / 200.0))
                let count: Int = (quotient < 2) ? 2 : quotient
                let count_f: Float = .init(count)
                
                let itemSize: NSCollectionLayoutSize = .init(
                    widthDimension: .fractionalWidth(.init(1.0 / count_f)),
                    heightDimension: .fractionalHeight(1.0)
                )
                
                let item: NSCollectionLayoutItem = .init(layoutSize: itemSize)
                
                let groupSize: NSCollectionLayoutSize = .init(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalWidth(.init(1.0 / count_f))
                )
                
                let group: NSCollectionLayoutGroup = .horizontal(layoutSize: groupSize, repeatingSubitem: item, count: count)
                let section: NSCollectionLayoutSection = .init(group: group)
                
                return section
            },
            configuration: configuration
        )
    }
    
    private func buildCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewCell, AssetsContentView.Item> {
        .init { [imageRequestOptions] cell, indexPath, itemIdentifier in
            cell.contentConfiguration = UIHostingConfiguration {
                AssetsContentView(item: itemIdentifier, imageRequestOptions: imageRequestOptions)
            }
            .margins([.all], .zero)
        }
    }
    
    private func buildAssetsDataSource() -> AssetsDataSource {
        let cellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, AssetsContentView.Item> = buildCellRegistration()
        
        let assetsDataSource: AssetsDataSource = .init(collectionView: collectionView, imageRequestOptions: imageRequestOptions) { (collectionView: UICollectionView, indexPath: IndexPath, fetchResult: PHFetchResult<PHAsset>, prefetchedImage: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage>?) in
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: .init(fetchResult: fetchResult, index: indexPath.item, prefetchedImage: prefetchedImage))
        } estimatedImageSizeProvider: { [weak self] (collectionView: UICollectionView, indexPath: IndexPath) in
            guard
                let size: CGSize = collectionView.visibleCells.first?.bounds.size,
                let scale: CGFloat = self?.traitCollection.displayScale
            else {
                return nil
            }
            
            return size * scale
        }
        
        return assetsDataSource
    }
    
    private nonisolated func select(collection: PHAssetCollection?) async throws {
        try await viewModel.load(collection: collection)
        
        await MainActor.run {
            var configuration: UIButton.Configuration = .plain()
            configuration.title = collection?.localizedTitle ?? "Recents"
            
            collectionsButton.configuration = configuration
            collectionsButton.sizeToFit()
        }
    }
}
