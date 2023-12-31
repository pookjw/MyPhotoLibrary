//
//  AssetsViewModel.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/11/23.
//

import Foundation
import Photos

actor AssetsViewModel {
    enum Error: Swift.Error {
        case cannotAccessPhotoLibrary
    }
    
    private let assetsDataSource: AssetsDataSource
    
    init(assetsDataSource: AssetsDataSource) {
        self.assetsDataSource = assetsDataSource
    }
    
    func load(collection: PHAssetCollection? = nil) async throws {
        try await requestAuthorization()
        await assetsDataSource.load(using: collection)
    }
    
    private func requestAuthorization(authorizationStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)) async throws {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            let requestedAuthorizationStatus: PHAuthorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            
            try await requestAuthorization(authorizationStatus: requestedAuthorizationStatus)
        case .restricted, .denied:
            throw Error.cannotAccessPhotoLibrary
        case .authorized, .limited:
            return
        @unknown default:
            throw Error.cannotAccessPhotoLibrary
        }
    }
}
