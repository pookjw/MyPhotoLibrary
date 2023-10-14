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
        let asset: PHAsset
        let prefetchedImage: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage>?
        let index: Int
    }
    
    private let item: Item
    private let imageRequestOptions: PHImageRequestOptions
    @State private var currentRequestID: PHImageRequestID?
    @State private var prefetchedImageSubject: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage>?
    @State private var image: UIImage?
    @State private var viewSize: CGSize = .zero
    @State private var opacity: Double = 1.0
    
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
            if let requestID: PHImageRequestID = oldValue.prefetchedImage?.value?.state.requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
            
            if let prefetchedImageSubject: CurrentValueAsyncThrowingSubject<AssetsDataSource.PrefetchedImage> = newValue.prefetchedImage {
                cancelCurrentRequest()
                self.prefetchedImageSubject = prefetchedImageSubject
            } else {
                prefetchedImageSubject = nil
                request()
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
            
            currentRequestID = prefetchedImage.state.requestID
            
            if viewSize * UIScreen.main.scale != prefetchedImage.requestedImageSize {
                prefetchedImageSubject.finish()
                request()
                return
            }
            
            image = prefetchedImage.state.image
            
            if case .prefetched(_, _) = prefetchedImage.state {
                prefetchedImageSubject.finish()
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
                    
                    if viewSize * UIScreen.main.scale != prefetchedImage.requestedImageSize {
                        prefetchedImageSubject.finish()
                        request()
                        return
                    }
                    
                    image = prefetchedImage.state.image
                    
                    if case .prefetched(_, _) = prefetchedImage.state {
                        prefetchedImageSubject.finish()
                        break
                    }
                }
            } catch is CancellationError {
                prefetchedImageSubject.finish()
                currentRequestID = nil
            } catch {
                prefetchedImageSubject.finish()
                request()
            }
        }
        .task(id: viewSize) {
            if
                let prefetchedImage: AssetsDataSource.PrefetchedImage = prefetchedImageSubject?.value,
                prefetchedImage.requestedImageSize != viewSize * UIScreen.main.scale
            {
                request()
            } else if currentRequestID == nil && image == nil {
                request()
            }
        }
    }
    
    @MainActor
    private func request() {
        cancelCurrentRequest()
        
        guard viewSize != .zero else {
            return
        }
        
//        print("ABC", item.index, viewSize)
        
        currentRequestID = PHImageManager
            .default()
            .requestImage(
                for: item.asset,
                targetSize: viewSize * UIScreen.main.scale,
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
                    image.prepareForDisplay { image in
                        Task { @MainActor in
                            guard currentRequestID == requestID else {
                                return
                            }
                            
                            self.image = image
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
}
