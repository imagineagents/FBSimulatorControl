/**
 * Copyright (c) 2017-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceLogCommands.h"

#import "FBDevice+Private.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceControlError.h"

@interface FBDeviceLogTerminationContinuation : NSObject <FBiOSTargetContinuation>

- (instancetype)initWithReader:(FBFileReader *)reader consumer:(id<FBFileConsumer>)consumer;

@property (nonatomic, strong, readonly) FBFileReader *reader;
@property (nonatomic, strong, readonly) id<FBFileConsumer> consumer;

@end

@implementation FBDeviceLogTerminationContinuation

- (instancetype)initWithReader:(FBFileReader *)reader consumer:(id<FBFileConsumer>)consumer
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _reader = reader;
  _consumer = consumer;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return self.reader.completed;
}

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeLogTail;
}

@end

@interface FBDeviceLogCommands()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceLogCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBLogCommands Implementation

- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments
{
  return [[FBDeviceControlError describeFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] failFuture];
}

- (FBFuture<id<FBiOSTargetContinuation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBFileConsumer>)consumer
{
  if (arguments.count == 0) {
    [self.device.logger logFormat:@"[FBDeviceLogCommands] Unsupported arguments: %@", arguments];
  }

  dispatch_queue_t queue = self.device.asyncQueue;
  return [[[self.device.amDevice futureForDeviceOperation:^id _Nonnull(CFTypeRef device, NSError **error) {
    NSString *name = @"com.apple.syslog_relay";
    CFTypeRef handle = 0;
    uint32_t unused;
    mach_error_t result = self.device.amDevice.calls.StartService(device, (__bridge CFStringRef)(name), &handle, &unused);
    if (result != 0) {
      return [FBFuture futureWithError:[FBDeviceControlError errorForFormat:@"Error when starting service %@: %d", name, result]];
    }

    int sock = (int)((uint32_t)handle);
    return [[NSFileHandle alloc] initWithFileDescriptor:sock closeOnDealloc:YES];
  }] onQueue:queue map:^(NSFileHandle *_Nonnull handle) {
    FBFileReader *reader = [FBFileReader readerWithFileHandle:handle consumer:consumer];
    return [[reader startReading] mapReplace:reader];
  }] onQueue:queue map:^(FBFileReader *reader) {
    return [[FBDeviceLogTerminationContinuation alloc] initWithReader:reader  consumer:consumer];
  }];
}

@end
