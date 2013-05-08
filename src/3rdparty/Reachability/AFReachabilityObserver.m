//
//  AFReachabilityObserver.m
//  RestKit
//
//  Created by Blake Watters on 9/14/10.
//  Copyright (c) 2009-2012 RestKit. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

#import "AFReachabilityObserver.h"
#include <netdb.h>
#include <arpa/inet.h>


@interface AFReachabilityObserver (Private)

@property (nonatomic, assign) SCNetworkReachabilityFlags reachabilityFlags;

// Internal initializer
- (id)initWithReachabilityRef:(SCNetworkReachabilityRef)reachabilityRef;
- (void)scheduleObserver;
- (void)unscheduleObserver;

@end

// Constants
NSString * const AFReachabilityDidChangeNotification = @"AFReachabilityDidChangeNotification";
NSString * const AFReachabilityFlagsUserInfoKey = @"AFReachabilityFlagsUserInfoKey";
NSString * const AFReachabilityWasDeterminedNotification = @"AFReachabilityWasDeterminedNotification";

static void ReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    AFReachabilityObserver *observer = (AFReachabilityObserver *)info;
    observer.reachabilityFlags = flags;
    
    [pool release];
}

#pragma mark -

@implementation AFReachabilityObserver

@synthesize host = _host;
@synthesize reachabilityFlags = _reachabilityFlags;
@synthesize reachabilityDetermined = _reachabilityDetermined;
@synthesize monitoringLocalWiFi = _monitoringLocalWiFi;

+ (AFReachabilityObserver *)reachabilityObserverForAddress:(const struct sockaddr *)address
{
    return [[[self alloc] initWithAddress:address] autorelease];
}

+ (AFReachabilityObserver *)reachabilityObserverForInternetAddress:(in_addr_t)internetAddress
{
    struct sockaddr_in address;
    bzero(&address, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(internetAddress);
    return [self reachabilityObserverForAddress:(struct sockaddr *)&address];
}

+ (AFReachabilityObserver *)reachabilityObserverForInternet
{
    return [self reachabilityObserverForInternetAddress:INADDR_ANY];
}

+ (AFReachabilityObserver *)reachabilityObserverForLocalWifi
{
    return [self reachabilityObserverForInternetAddress:IN_LINKLOCALNETNUM];
}

+ (AFReachabilityObserver *)reachabilityObserverForHost:(NSString *)hostNameOrIPAddress
{
    return [[[self alloc] initWithHost:hostNameOrIPAddress] autorelease];
}

- (id)initWithAddress:(const struct sockaddr *)address
{
    self = [super init];
    if (self) {
        _reachabilityRef = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, address);
        if (_reachabilityRef == NULL) {
            [self release];
            self = nil;
        } else {
            // For technical details regarding link-local connections, please
            // see the following source file at Apple's open-source site.
            //
            //    http://www.opensource.apple.com/source/bootp/bootp-89/IPConfiguration.bproj/linklocal.c
            //
            _monitoringLocalWiFi = address->sa_len == sizeof(struct sockaddr_in) && address->sa_family == AF_INET && IN_LINKLOCAL(ntohl(((const struct sockaddr_in *)address)->sin_addr.s_addr));
            
            // Save the IP address
            char str[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((const struct sockaddr_in *)address)->sin_addr, str, INET_ADDRSTRLEN);
            _host = [[NSString alloc] initWithCString:str encoding:NSUTF8StringEncoding];
            
            if (_monitoringLocalWiFi) {
                NSLog(@"Reachability observer initialized for Local Wifi");
            } else if (address->sa_len == sizeof(struct sockaddr_in) && address->sa_family == AF_INET) {
                NSLog(@"Reachability observer initialized with IP address: %@.", _host);
            }
            
            // We can immediately determine reachability to an IP address
            dispatch_async(dispatch_get_main_queue(), ^{
                // Obtain the flags after giving other objects a chance to observe us
                [self getFlags];
            });
            
            // Schedule the observer
            [self scheduleObserver];
        }
    }
    return self;
}

- (id)initWithHost:(NSString *)hostNameOrIPAddress
{
    // Determine if the string contains a hostname or IP address
    struct sockaddr_in sa;
    char *hostNameOrIPAddressCString = (char *)[hostNameOrIPAddress UTF8String];
    int result = inet_pton(AF_INET, hostNameOrIPAddressCString, &(sa.sin_addr));
    if (result != 0) {
        // IP Address
        struct sockaddr_in remote_saddr;
        
        bzero(&remote_saddr, sizeof(struct sockaddr_in));
        remote_saddr.sin_len = sizeof(struct sockaddr_in);
        remote_saddr.sin_family = AF_INET;
        inet_aton(hostNameOrIPAddressCString, &(remote_saddr.sin_addr));
        
        return [self initWithAddress:(struct sockaddr *)&remote_saddr];
    }
    
    // Hostname
    self = [self init];
    if (self) {
        _host = [hostNameOrIPAddress retain];
        _reachabilityRef = SCNetworkReachabilityCreateWithName(CFAllocatorGetDefault(), hostNameOrIPAddressCString);
        NSLog(@"Reachability observer initialized with hostname %@", hostNameOrIPAddress);
        if (_reachabilityRef == NULL) {
            NSLog(@"Unable to initialize reachability reference");
            [self release];
            self = nil;
        } else {
            [self scheduleObserver];
        }
    }
    
    return self;
}

- (void)dealloc
{
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self unscheduleObserver];
    if (_reachabilityRef) {
        CFRelease(_reachabilityRef);
    }
    [_host release];
    
    [super dealloc];
}

- (BOOL)getFlags
{
    SCNetworkReachabilityFlags flags = 0;
    BOOL result = SCNetworkReachabilityGetFlags(_reachabilityRef, &flags);
    if (result) self.reachabilityFlags = flags;
    return result;
}

- (NSString *)stringFromNetworkStatus:(AFReachabilityNetworkStatus)status
{
    switch (status) {
        case AFReachabilityIndeterminate:
            return @"AFReachabilityIndeterminate";
            break;
            
        case AFReachabilityNotReachable:
            return @"AFReachabilityNotReachable";
            break;
            
        case AFReachabilityReachableViaWiFi:
            return @"AFReachabilityReachableViaWiFi";
            break;
            
        case AFReachabilityReachableViaWWAN:
            return @"AFReachabilityReachableViaWWAN";
            break;
            
        default:
            break;
    }
    
    return nil;
}

- (NSString *)reachabilityFlagsDescription
{
    return [NSString stringWithFormat:@"%c%c %c%c%c%c%c%c%c",
#if TARGET_OS_IPHONE
            (_reachabilityFlags & kSCNetworkReachabilityFlagsIsWWAN)               ? 'W' : '-',
#else
            // If we are not on iOS, always output a dash for WWAN
            '-',
#endif
            (_reachabilityFlags & kSCNetworkReachabilityFlagsReachable)            ? 'R' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsTransientConnection)  ? 't' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionRequired)   ? 'c' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionOnTraffic)  ? 'C' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsInterventionRequired) ? 'i' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionOnDemand)   ? 'D' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsIsLocalAddress)       ? 'l' : '-',
            (_reachabilityFlags & kSCNetworkReachabilityFlagsIsDirect)             ? 'd' : '-'];
}

- (AFReachabilityNetworkStatus)networkStatus
{
    NSAssert(_reachabilityRef != NULL, @"currentNetworkStatus called with NULL reachabilityRef");
    AFReachabilityNetworkStatus status = AFReachabilityNotReachable;
    
    if (!self.reachabilityDetermined) {
        
        return AFReachabilityIndeterminate;
    }
    
    // If we are observing WiFi, we are only reachable via WiFi when flags are direct
    if (self.isMonitoringLocalWiFi) {
        if ((_reachabilityFlags & kSCNetworkReachabilityFlagsReachable) && (_reachabilityFlags & kSCNetworkReachabilityFlagsIsDirect)) {
            // <-- reachable AND direct
            status = AFReachabilityReachableViaWiFi;
        } else {
            // <-- NOT reachable OR NOT direct
            status = AFReachabilityNotReachable;
        }
    } else {
        if ((_reachabilityFlags & kSCNetworkReachabilityFlagsReachable)) {
            // <-- reachable
#if TARGET_OS_IPHONE
            if ((_reachabilityFlags & kSCNetworkReachabilityFlagsIsWWAN)) {
                // <-- reachable AND is wireless wide-area network (iOS only)
                status = AFReachabilityReachableViaWWAN;
            } else {
#endif
                // <-- reachable AND is NOT wireless wide-area network (iOS only)
                if ((_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionOnTraffic) || (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionOnDemand)) {
                    // <-- reachable, on-traffic OR on-demand connection
                    if ((_reachabilityFlags & kSCNetworkReachabilityFlagsInterventionRequired)) {
                        // <-- reachable, on-traffic OR on-demand connection, intervention required
                        status = (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionRequired) ? AFReachabilityNotReachable : AFReachabilityReachableViaWiFi;
                    } else {
                        // <-- reachable, on-traffic OR on-demand connection, intervention NOT required
                        status = AFReachabilityReachableViaWiFi;
                    }
                } else {
                    // <-- reachable, NOT on-traffic OR on-demand connection
                    status = (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionRequired) ? AFReachabilityNotReachable : AFReachabilityReachableViaWiFi;
                }
#if TARGET_OS_IPHONE
            }
#endif
        } else {
            // <-- NOT reachable
            status = AFReachabilityNotReachable;
        }
    }
    
    NSLog(@"Reachability observer %@ determined networkStatus = %@", self, [self stringFromNetworkStatus:status]);
    return status;
}

#pragma Reachability Flag Introspection

- (void)validateIntrospection
{
    NSAssert(_reachabilityRef != NULL, @"connectionRequired called with NULL reachabilityRef");
    NSAssert(self.isReachabilityDetermined, @"Cannot inspect reachability state: no reachabilityFlags available. Be sure to check isReachabilityDetermined");
}

- (BOOL)isNetworkReachable
{
    [self validateIntrospection];
    BOOL reachable = (AFReachabilityNotReachable != [self networkStatus]);
    return reachable;
}

- (BOOL)isConnectionRequired
{
    [self validateIntrospection];
    BOOL required = (_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionRequired);
    
    return required;
}

- (BOOL)isReachableViaWWAN
{
    [self validateIntrospection];
    return self.networkStatus == AFReachabilityReachableViaWWAN;
}

- (BOOL)isReachableViaWiFi
{
    [self validateIntrospection];
    return self.networkStatus == AFReachabilityReachableViaWiFi;
}

- (BOOL)isConnectionOnDemand
{
    [self validateIntrospection];
    return ((_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionRequired) &&
            (_reachabilityFlags & (kSCNetworkReachabilityFlagsConnectionOnTraffic |
                                   kSCNetworkReachabilityFlagsConnectionOnDemand)));
    
}

- (BOOL)isInterventionRequired
{
    [self validateIntrospection];
    return ((_reachabilityFlags & kSCNetworkReachabilityFlagsConnectionRequired) &&
            (_reachabilityFlags & kSCNetworkReachabilityFlagsInterventionRequired));
}

#pragma mark Observer scheduling

- (void)scheduleObserver
{
    SCNetworkReachabilityContext context = { .info = self };
    if (! SCNetworkReachabilitySetCallback(_reachabilityRef, ReachabilityCallback, &context)) {
        return;
    }
    
    if (! SCNetworkReachabilitySetDispatchQueue(_reachabilityRef, dispatch_get_main_queue())) {
        
        return;
    }
}

- (void)unscheduleObserver
{
    if (_reachabilityRef)
    {
        if (! SCNetworkReachabilitySetDispatchQueue(_reachabilityRef, NULL))
        {
            
            return;
        }
    }
}

- (void)setReachabilityFlags:(SCNetworkReachabilityFlags)reachabilityFlags
{
    // Save the reachability flags
    _reachabilityFlags = reachabilityFlags;
    
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:reachabilityFlags] forKey:AFReachabilityFlagsUserInfoKey];
    
    if (! self.reachabilityDetermined) {
        _reachabilityDetermined = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:AFReachabilityWasDeterminedNotification object:self userInfo:userInfo];
    }
    
    // Post a notification to notify the client that the network reachability changed.
    [[NSNotificationCenter defaultCenter] postNotificationName:AFReachabilityDidChangeNotification object:self userInfo:userInfo];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p host=%@ isReachabilityDetermined=%@ isMonitoringLocalWiFi=%@ reachabilityFlags=%@>",
            NSStringFromClass([self class]), self, self.host, self.isReachabilityDetermined ? @"YES" : @"NO",
            self.isMonitoringLocalWiFi ? @"YES" : @"NO", [self reachabilityFlagsDescription]];
}

@end
