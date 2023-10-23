//
//  AssetsContentView.swift
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/12/23.
//

import SwiftUI
import Photos

struct AssetsContentView: View {
    struct Item: Equatable {
        let fetchResult: PHFetchResult<PHAsset>
        let index: Int
        let prefetchedImage: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage>?
    }
    
    private let item: Item
    private let imageRequestOptions: PHImageRequestOptions
    @State private var currentRequestID: PHImageRequestID?
    @State private var prefetchedImageSubject: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage>?
    @State private var image: UIImage?
    @State private var viewSize: CGSize = .zero
    @State private var opacity: Double = 1.0
    @Environment(\.displayScale) private var displayScale: CGFloat
    
    init(item: Item, imageRequestOptions: PHImageRequestOptions) {
        self.item = item
        self.imageRequestOptions = imageRequestOptions
    }
    
    var body: some View {
        Group {
            if let image: UIImage {
                Color
                    .clear
                    .aspectRatio(1.0, contentMode: .fit)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    )
                    .clipShape(Rectangle())
            } else {
                Color.clear
            }
        }
        .opacity(opacity)
        .background {
            GeometryReader { proxy in
                Color
                    .clear
                    .onChange(of: proxy.size, initial: true) { oldValue, newValue in
                        guard viewSize != newValue else { return }
                        viewSize = newValue
                    }
            }
        }
        .onChange(of: image, initial: true) { oldValue, newValue in
            if newValue == nil {
                opacity = .zero
            } else {
                withAnimation(.easeInOut(duration: 0.1)) {
                    opacity = 1.0
                }
            }
        }
        .onChange(of: item, initial: true) { oldValue, newValue in
            guard oldValue != newValue else {
                return
            }
            
            image = nil
            oldValue.prefetchedImage?.finish()
        }
        .task(id: item) {
            if let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage> = item.prefetchedImage {
                cancelCurrentRequest()
                self.prefetchedImageSubject = prefetchedImageSubject
            } else {
                prefetchedImageSubject = nil
                await request(asset: asset)
            }
        }
        .task(id: prefetchedImageSubject) {
            guard let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage> else {
                return
            }
            
            guard let prefetchedImage: AssetsDataSource.PrefetchedImage = prefetchedImageSubject.value else {
                fatalError()
            }
            
            //
            
            guard !Task.isCancelled else {
                cancelCurrentRequest()
                prefetchedImageSubject.finish()
                return
            }
            
            if viewSize * displayScale != prefetchedImage.requestedImageSize {
                await request(asset: asset)
                prefetchedImageSubject.finish()
                return
            }
            
            image = prefetchedImage.state.image
            
            if case .prefetched(_, _) = prefetchedImage.state {
                prefetchedImageSubject.finish()
                return
            }
            
            guard !prefetchedImageSubject.isFinished else {
                return
            }
            
            //
            
            do {
                for try await prefetchedImage in prefetchedImageSubject() {
                    guard !Task.isCancelled else {
                        cancelCurrentRequest()
                        prefetchedImageSubject.finish()
                        break
                    }
                    
                    if viewSize * displayScale != prefetchedImage.requestedImageSize {
                        await request(asset: asset)
                        prefetchedImageSubject.finish()
                        return
                    }
                    
                    image = prefetchedImage.state.image
                    
                    if case .prefetched(_, _) = prefetchedImage.state {
                        prefetchedImageSubject.finish()
                        break
                    }
                }
            } catch is CancellationError {
                cancelCurrentRequest()
                prefetchedImageSubject.finish()
                currentRequestID = nil
            } catch {
                await request(asset: asset)
                prefetchedImageSubject.finish()
            }
        }
        .task(id: viewSize) {
            if
                let prefetchedImage: AssetsDataSource.PrefetchedImage = prefetchedImageSubject?.value,
                prefetchedImage.requestedImageSize != viewSize * displayScale
            {
                await request(asset: asset)
            } else if currentRequestID == nil && image == nil {
                await request(asset: asset)
            }
        }
        .task(id: displayScale) {
            if
                let prefetchedImage: AssetsDataSource.PrefetchedImage = prefetchedImageSubject?.value,
                prefetchedImage.requestedImageSize != viewSize * displayScale
            {
                await request(asset: asset)
            } else if currentRequestID == nil && image == nil {
                await request(asset: asset)
            }
        }
    }
    
    @MainActor
    private func request(asset: PHAsset) {
        cancelCurrentRequest()
        
        guard viewSize != .zero else {
            return
        }
        
        currentRequestID = PHImageManager
            .default()
            .requestImage(
                for: asset,
                targetSize: viewSize * displayScale,
//                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: imageRequestOptions
            ) { image, userInfo in
                guard 
                    !(userInfo?[PHImageCancelledKey] as? Bool ?? false),
                    let requestID: PHImageRequestID = userInfo?[PHImageResultRequestIDKey] as? PHImageRequestID
                else {
                    return
                }
                
                if let image: UIImage {
                    Task { @MainActor in
                        guard currentRequestID == requestID else {
                            return
                        }
                        
                        image.prepareForDisplay { image in
                            Task { @MainActor in
                                guard currentRequestID == requestID else {
                                    return
                                }
                                
                                self.image = image
                            }
                        }
                    }
                } else {
                    self.image = nil
                }
            }
    }
    
    private func cancelCurrentRequest() {
        if let currentRequestID: PHImageRequestID {
            PHImageManager.default().cancelImageRequest(currentRequestID)
        }
        
        currentRequestID = nil
    }
    
    private var asset: PHAsset {
        get async {
            item.fetchResult.ff_PHAsset(at: item.index)
        }
    }
}
