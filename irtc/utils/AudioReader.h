//
//  AudioReader.h
//  irtc
//
//  Created by ideawu on 3/10/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// 将音频文件读取成 SampleBuffer
@interface AudioReader : NSObject

@property AudioStreamBasicDescription format;

+ (AudioReader *)readerWithFile:(NSString *)file;

- (id)initWithFile:(NSString *)file;

- (CMSampleBufferRef)nextSampleBuffer;
- (NSData *)nextSampleData;

@end
