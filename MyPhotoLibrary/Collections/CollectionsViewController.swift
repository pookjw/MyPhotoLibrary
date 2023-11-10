//
//  CollectionsViewController.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/13/23.
//

import UIKit
import Photos

@MainActor
final class CollectionsViewController: UIViewController {
    let selectedCollectionSubject: CurrentValueAsyncSubject<PHAssetCollection?>
    
    @ViewLoading private var collectionView: UICollectionView
    @ViewLoading private var viewModel: CollectionsViewModel
    
    private var loadingTask: Task<Void, Never>? {
        willSet {
            loadingTask?.cancel()
        }
    }
    
    init(selectedCollection: PHAssetCollection?) {
        selectedCollectionSubject = .init(value: selectedCollection)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        loadingTask?.cancel()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupViewModel()
        setupAttributes()
        load()
    }
    
    private func setupCollectionView() {
        let listConfiguration: UICollectionLayoutListConfiguration = .init(appearance: .insetGrouped)
        let collectionViewLayout: UICollectionViewCompositionalLayout = .list(using: listConfiguration)
        let collectionView: UICollectionView = .init(frame: view.bounds, collectionViewLayout: collectionViewLayout)
        
        collectionView.delegate = self
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        
        view.addSubview(collectionView)
        self.collectionView = collectionView
    }
    
    private func setupViewModel() {
        let collectionsDataSource: CollectionsDataSource = buildCollectionsDataSource()
        let viewModel: CollectionsViewModel = .init(collectionsDataSource: collectionsDataSource)
        self.viewModel = viewModel
    }
    
    private func setupAttributes() {
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
    }
    
    private func buildCollectionsDataSource() -> CollectionsDataSource {
        let cellRegistration: UICollectionView.CellRegistration<UICollectionViewListCell, PHAssetCollection> = buildCellRegistration()
        
        let dataSource: CollectionsDataSource = .init(collectionView: collectionView) { collectionView, indexPath, fetchResult in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: fetchResult.object(at: indexPath.item))
        } supplementaryViewProvider: { collectionView, elementKind, indexPath in
            fatalError()
        }

        
        return dataSource
    }
    
    private func load() {
        loadingTask = .init { [viewModel] in
            try! await viewModel.load()
            
            if 
                let selectedCollection: PHAssetCollection = await selectedCollectionSubject.value ?? nil,
                let indexPath: IndexPath = await viewModel.indexPath(for: selectedCollection)
            {
                collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .init(rawValue: .zero))
            }
        }
    }
    
    private func buildCellRegistration() -> UICollectionView.CellRegistration<UICollectionViewListCell, PHAssetCollection> {
        .init { cell, indexPath, itemIdentifier in
            var contentConfiguration: UIListContentConfiguration = cell.defaultContentConfiguration()
            contentConfiguration.text = itemIdentifier.localizedTitle
            cell.contentConfiguration = contentConfiguration
        }
    }
}

extension CollectionsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Task {
            let selectedCollection: PHAssetCollection? = await viewModel.collection(at: indexPath)
            await selectedCollectionSubject.yield(selectedCollection)
        }
        
        dismiss(animated: true)
    }
}
