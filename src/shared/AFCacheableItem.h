/*
 *
 * Copyright 2008 Artifacts - Fine Software Development
 * http://www.artifacts.de
 * Author: Michael Markowski (m.markowski@artifacts.de)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "AFCacheableItemInfo.h"

#ifdef USE_TOUCHXML
#import "TouchXML.h"
#endif

@class AFCache;
@class AFCacheableItem;
@protocol AFCacheableItemDelegate;

typedef NS_ENUM(NSUInteger, AFCacheStatus)  {
	kCacheStatusNew = 0,
	kCacheStatusFresh = 1, // written into cacheableitem when item is fresh, either after fetching it for the first time or by revalidation.
	kCacheStatusModified = 2, // if ims request returns status 200
	kCacheStatusNotModified = 4,
	kCacheStatusRevalidationPending = 5,
	kCacheStatusStale = 6,
	kCacheStatusDownloading = 7, // item is not fully downloaded
};

#if NS_BLOCKS_AVAILABLE
typedef void (^AFCacheableItemBlock)(AFCacheableItem* item);
#endif


@interface AFCacheableItem : NSObject {
}

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) NSError *error;

@property (nonatomic, readonly) AFCacheableItemInfo *info;
@property (nonatomic, retain)   NSDictionary* userData;


@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;

@property (nonatomic, readonly) uint64_t currentContentLength;
@property (nonatomic, readonly) AFCacheStatus cacheStatus;


@property (nonatomic, readonly) BOOL isFresh;
@property (nonatomic, readonly) BOOL isComplete;
@property (nonatomic, readonly) BOOL isPackageArchive;
@property (nonatomic, readonly) BOOL servedFromCache;
@property (nonatomic, readonly) BOOL isDownloading;


#if NS_BLOCKS_AVAILABLE
@property (nonatomic, copy) AFCacheableItemBlock completionBlock;
@property (nonatomic, copy) AFCacheableItemBlock failBlock;
@property (nonatomic, copy) AFCacheableItemBlock progressBlock;
#endif


@end