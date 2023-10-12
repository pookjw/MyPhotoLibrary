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
    private var loadingTask: Task<Void, Never>?
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
    
    deinit {
        loadingTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAttributes()
        setupCollectionView()
        setupViewModel()
        load()
    }
    
    private func setupAttributes() {
        view.backgroundColor = .systemBackground
    }
    
    private func setupCollectionView() {
        let collectionViewLayout: UICollectionViewLayout = buildCollectionViewLayout()
        let collectionView: UICollectionView = .init(frame: view.bounds, collectionViewLayout: collectionViewLayout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        
        view.addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    private func setupViewModel() {
        let assetsDataSource: AssetsDataSource = buildAssetsDataSource()
        let viewModel: AssetsViewModel = .init(assetsDataSource: assetsDataSource)
        self.viewModel = viewModel
    }
    
    private func load() {
        loadingTask = .init { [viewModel] in
            try! await viewModel.requestAuthorization()
            try! await viewModel.assetsDataSource.load(using: nil)
        }
    }
    
    private func buildCollectionViewLayout() -> UICollectionViewLayout {
        let configuration: UICollectionViewCompositionalLayoutConfiguration = .init()
        configuration.scrollDirection = .vertical
        
        return UICollectionViewCompositionalLayout(
            sectionProvider: { sectionIndex, environment in
                let itemSize: NSCollectionLayoutSize = .init(
                    widthDimension: .fractionalWidth(1.0 / 3.0),
                    heightDimension: .fractionalHeight(1.0)
                )
                let item: NSCollectionLayoutItem = .init(layoutSize: itemSize)
                
                let groupSize: NSCollectionLayoutSize = .init(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .fractionalWidth(1.0 / 3.0)
                )
                
                let group: NSCollectionLayoutGroup = .horizontal(layoutSize: groupSize, repeatingSubitem: item, count: 3)
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
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: .init(fetchResult: fetchResult, prefetchedImage: prefetchedImage, index: indexPath.item))
        } estimatedImageSizeProvider: { (collectionView: UICollectionView, indexPath: IndexPath) in
            guard let size: CGSize = collectionView.visibleCells.first?.bounds.size else {
                return nil
            }
            
            return size * UIScreen.main.scale
        }
        
        return assetsDataSource
    }
}
