//
//  PHFetchResult+FastFetching.h
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/15/23.
//

#import <Photos/Photos.h>

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

@interface PHFetchResult (FastFetching)
- (PHAsset *)ff_PHAssetAtIndex:(NSInteger)index;
@end

NS_HEADER_AUDIT_END(nullability, sendability)
