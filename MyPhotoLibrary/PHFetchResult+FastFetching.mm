//
//  PHFetchResult+FastFetching.mm
//  MyPhotoLibrary
//
//  Created by Jinwoo Kim on 10/15/23.
//

#import "PHFetchResult+FastFetching.h"
#import <objc/message.h>

@implementation PHFetchResult (FastFetching)

#if __has_feature(objc_arc)
#error "ARC is not supported."
#else
- (PHAsset *)ff_PHAssetAtIndex:(NSInteger)index {
    id objectID = reinterpret_cast<id (*)(PHFetchResult *, SEL, NSUInteger)>(objc_msgSend)(self, NSSelectorFromString(@"objectIDAtIndex:"), index);
    auto fetchResult = reinterpret_cast<PHFetchResult<PHAsset *> * (*)(Class, SEL, NSArray *, PHFetchOptions *)>(objc_msgSend)(PHAsset.class, NSSelectorFromString(@"fetchAssetsWithObjectIDs:options:"), @[objectID], nil);
    return fetchResult.firstObject;
}
#endif

@end
