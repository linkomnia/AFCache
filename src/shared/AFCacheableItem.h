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

enum kCacheStatus {
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
	NSURL *url;
    NSURLRequest *request;
	NSData *data;
	AFCache *cache;
	id <AFCacheableItemDelegate> delegate;
	BOOL persistable;
	BOOL ignoreErrors;
    BOOL justFetchHTTPHeader;
	SEL connectionDidFinishSelector;
	SEL connectionDidFailSelector;
	NSError *error;
	id userData;
	
	// validUntil holds the calculated expire date of the cached object.
	// It is either equal to Expires (if Expires header is set), or the date
	// based on the request time + max-age (if max-age header is set).
	// If neither Expires nor max-age is given or if the resource must not
	// be cached valitUntil is nil.	
	NSDate *validUntil;
	int cacheStatus;
	AFCacheableItemInfo *info;
	int tag; // for debugging and testing purposes
	BOOL isPackageArchive;
	uint64_t currentContentLength;
    
    NSFileHandle*   fileHandle;
	
	/*
	 Some data for the HTTP Basic Authentification
	 */
	NSString *username;
	NSString *password;
    
    BOOL    isRevalidating;
    NSURLRequest *IMSRequest; // last If-modified-Since Request. Just for debugging purposes, will not be persisted.
    BOOL servedFromCache;
    BOOL URLInternallyRewritten;
    BOOL    canMapData;
 
#if NS_BLOCKS_AVAILABLE
    //block to execute when request completes successfully
	AFCacheableItemBlock completionBlock;
    AFCacheableItemBlock failBlock;
    AFCacheableItemBlock progressBlock;
#endif
}

@property (nonatomic, readonly) NSURL *url;
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) NSError *error;
@property (nonatomic, readonly) NSDate *validUntil;

@property (nonatomic, readonly) AFCacheableItemInfo *info;
@property (nonatomic, retain) NSDictionary* userData;


@property (nonatomic, retain) NSString *username;
@property (nonatomic, retain) NSString *password;

@property (nonatomic, readonly) uint64_t currentContentLength;
@property (nonatomic, readonly) int cacheStatus;
@property (nonatomic, readonly) BOOL isCachedOnDisk;
@property (nonatomic, readonly) BOOL isFresh;
@property (nonatomic, readonly) BOOL isComplete;
@property (nonatomic, readonly) BOOL isDataLoaded;
@property (nonatomic, readonly) BOOL isPackageArchive;
@property (nonatomic, readonly) BOOL servedFromCache;

@end