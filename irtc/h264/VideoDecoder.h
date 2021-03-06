//
//  VideoDecoder.h
//  irtc
//
//  Created by ideawu on 3/7/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

/*
 Annex-B byte stream format: with start code(0x000001 or 0x00000001)
 AVCC format: start with length(mostly 4 bytes)
 */

@interface VideoDecoder : NSObject

- (BOOL)isReadyForFrame;

/**
 set SPS PPS without header
 */
- (void)setSps:(NSData *)sps pps:(NSData *)pps;

// CVImageBufferRef 即是 CVPixelBufferRef
- (void)start:(void (^)(CVPixelBufferRef pixelBuffer, double pts, double duration))callback;
- (void)shutdown;

/**
 Must be 4 bytes length AVCC nalus
 */
- (void)decode:(NSData *)frame;
/**
 Must be 4 bytes length AVCC nalus
 */
- (void)decode:(NSData *)frame pts:(double)pts;
/**
 Must be 4 bytes length AVCC nalus
 */
- (void)decode:(NSData *)frame pts:(double)pts duration:(double)duration;


/*
 http://stackoverflow.com/questions/29525000/how-to-use-videotoolbox-to-decompress-h-264-video-stream/
 
 Video Deocde Acceleration Framework for Mac
 https://developer.apple.com/library/mac/technotes/tn2267/_index.html
 */
/*
 Emulation Prevention bytes: 如果数据中包括 00 00, 那么必须在(00 00)后面插入 03, 
 // H.264
 帧分隔符: 00 00 00 01 或 00 00 01
 PTS: Present Time Stamp
 SPS: Sequence Parameter Set
 PPS: Picture Parameter Set
 NAL: Network Abstract Layer
 VCL: Video Coding Layer
 POC: ?
 IDR: Instantaneous Decoder Refresh
	IDR = SPS + PPS + SEI + I frame + frames
 SEI: Supplemental Enhancement Information
 RBSP: Raw Byte Sequence Payload
 
 MB: MacroBlock
 frame = slices+

 NAL Unit 格式: 帧分隔符(4/3) + type(1) + ...
	type: null(1 bit) + 参考级别(2 bits) + type(5 bits)
 0x.7 - SPS
 0x.8 - PPS
 0x.5 - I Frame
 0x.6 - SEI
 0x.9 - Separator

 Sequence Parameter Set (SPS). This non-VCL NALU contains information required to configure the decoder such as profile, level, resolution, frame rate.
 Picture Parameter Set (PPS). Similar to the SPS, this non-VCL contains information on entropy coding mode, slice groups, motion prediction and deblocking filters.
 Instantaneous Decoder Refresh (IDR). This VCL NALU is a self contained image slice. That is, an IDR can be decoded and displayed without referencing any other NALU save SPS and PPS.
 Access Unit Delimiter (AUD). An AUD is an optional NALU that can be use to delimit frames in an elementary stream. It is not required (unless otherwise stated by the container/protocol, like TS), and is often not included in order to save space, but it can be useful to finds the start of a frame without having to fully parse each NALU.
 */

@end
