//
//  AACCodec.m
//  irtc
//
//  Created by ideawu on 3/11/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import "AACCodec.h"

@interface AACCodec(){
	
	BOOL _running;
	NSCondition *_condition;
	
	NSMutableArray *_samples;
	NSData *_processing_data;
	
	void (^_callback)(NSData *data, double duration);
}
@property (nonatomic) AudioStreamBasicDescription srcFormat;
@property (nonatomic) AudioStreamBasicDescription dstFormat;

@property (nonatomic) AudioConverterRef converter;
@property (nonatomic) uint8_t *aacBuffer;
@property (nonatomic) NSUInteger aacBufferSize;
@property (nonatomic) char *pcmBuffer;
@property (nonatomic) size_t pcmBufferSize;
@property (nonatomic) int sampleRate;
@property (nonatomic) int bitrate;
@property (nonatomic) dispatch_queue_t encoderQueue;
@end


@implementation AACCodec

- (id)init{
	self = [super init];
	
	// if encoding to AAC set the bitrate
	// kAudioConverterEncodeBitRate is a UInt32 value containing the number of bits per second to aim for when encoding data
	// when you explicitly set the bit rate and the sample rate, this tells the encoder to stick with both bit rate and sample rate
	//     but there are combinations (also depending on the number of channels) which will not be allowed
	// if you do not explicitly set a bit rate the encoder will pick the correct value for you depending on samplerate and number of channels
	// bit rate also scales with the number of channels, therefore one bit rate per sample rate can be used for mono cases
	//    and if you have stereo or more, you can multiply that number by the number of channels.
	_sampleRate = 22050;
	if(_sampleRate >= 44100){
		_bitrate = 192000; // 192kbs
	}else if(_sampleRate < 22000){
		_bitrate = 32000; // 32kbs
	}else{
		_bitrate = 64000; // 64kbs
	}
	
	_pcmBufferSize = 0;
	_pcmBuffer = NULL;
	
	_aacBufferSize = 8192;
	_aacBuffer = (uint8_t *)malloc(_aacBufferSize * sizeof(uint8_t));
	memset(_aacBuffer, 0, _aacBufferSize);
	
	_converter = NULL;
	
	_condition = [[NSCondition alloc] init];
	_samples = [[NSMutableArray alloc] init];
	
	memset(&_srcFormat, 0, sizeof(AudioStreamBasicDescription));
	memset(&_dstFormat, 0, sizeof(AudioStreamBasicDescription));
	
	return self;
}

- (void)start:(void (^)(NSData *data, double duration))callback{
	_callback = callback;
	_running = YES;
	[self performSelectorInBackground:@selector(run) withObject:nil];
}

- (void)shutdown{
	_running = NO;
	[_condition lock];
	[_condition broadcast];
	[_condition unlock];
}

- (void)dealloc{
	if(_converter){
		AudioConverterDispose(_converter);
	}
	if(_aacBuffer){
		free(_aacBuffer);
	}
}

- (void)setupCodecWithFormat:(AudioStreamBasicDescription)srcFormat dstFormat:(AudioStreamBasicDescription)dstFormat{
	_srcFormat = srcFormat;
	_dstFormat = dstFormat;
	[self createConverter];
}

- (void)setupCodecFromSampleBuffer:(CMSampleBufferRef)sampleBuffer{
	OSStatus err;
	UInt32 size;
	_srcFormat = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	
	// kAudioFormatMPEG4AAC_HE does not work. Can't find `AudioClassDescription`. `mFormatFlags` is set to 0.
	_dstFormat.mFormatID = kAudioFormatMPEG4AAC;
	_dstFormat.mChannelsPerFrame = _srcFormat.mChannelsPerFrame;
	// 如果设置 bitrate, 应该让编码器自己决定 samplerate
	//	if(_bitrate > 0){
	//		_format.mSampleRate = 0;
	//	}else{
	//		_format.mSampleRate = _srcFormat.mSampleRate;
	//	}
	_dstFormat.mSampleRate = _srcFormat.mSampleRate;
	//_format.mFramesPerPacket = 1024;
	// 不能设置
	//_format.mBitsPerChannel = 16;
	//_format.mBytesPerPacket = _format.mChannelsPerFrame * (_format.mBitsPerChannel / 8);
	
	// use AudioFormat API to fill out the rest of the description
	size = sizeof(_dstFormat);
	err = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &_dstFormat);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
	}
	
	[self createConverter];
}

- (void)encodePCM:(NSData *)raw{
	[self appendData:raw];
}


- (void)decodeAAC:(NSData *)aac{
	[self appendData:aac];
}

- (void)appendData:(NSData *)data{
	[_condition lock];
	{
		[_samples addObject:data];
		//NSLog(@"signal _samples: %d", (int)_samples.count);
		[_condition signal];
	}
	[_condition unlock];
}

- (void)run{
	OSStatus status;
	NSError *error = nil;
	
	while(_running){
		AudioBufferList outAudioBufferList;
		outAudioBufferList.mNumberBuffers = 1;
		outAudioBufferList.mBuffers[0].mNumberChannels = _dstFormat.mChannelsPerFrame;
		outAudioBufferList.mBuffers[0].mDataByteSize = (UInt32)_aacBufferSize;
		outAudioBufferList.mBuffers[0].mData = _aacBuffer;
		
		UInt32 outPackets = 1;
		status = AudioConverterFillComplexBuffer(_converter,
												 inInputDataProc,
												 (__bridge void *)(self),
												 &outPackets,
												 &outAudioBufferList,
												 NULL);
		if(status != noErr){
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			NSLog(@"AudioConverterFillComplexBuffer error: %@", error);
			NSLog(@"dispose converter");
			AudioConverterDispose(_converter);
			_converter = NULL;
			_running = NO;
			continue;
		}
		int outFrames = _dstFormat.mFramesPerPacket * outPackets;
		NSLog(@"outPackets: %d, frames: %d", (int)outPackets, outFrames);
		
		if (status == 0) {
			NSData *data = [NSData dataWithBytes:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize];
			
			// deal with data
			double duration = outFrames / _dstFormat.mSampleRate;
			//NSLog(@"AAC ready, pts: %f, duration: %f, bytes: %d", _pts, duration, (int)data.length);
			if(_callback){
				_callback(data, duration);
			}
		} else {
			error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
			NSLog(@"decode error: %@", error);
		}
	}
}

// AudioConverterComplexInputDataProc
static OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
								UInt32 *ioNumberDataPackets,
								AudioBufferList *ioData,
								AudioStreamPacketDescription **outDataPacketDescription,
								void *inUserData){
	AACCodec *me = (__bridge AACCodec *)(inUserData);
	UInt32 requestedPackets = *ioNumberDataPackets;
	//NSLog(@"Number of packets requested: %d", (unsigned int)requestedPackets);
	int ret = [me copyData:ioData requestedPackets:requestedPackets];
	if(ret == -1){
		*ioNumberDataPackets = 0;
		return -1;
	}
	*ioNumberDataPackets = ret;
	//NSLog(@"Copied %d packets into ioData, requested: %d", ret, requestedPackets);
	return noErr;
}

- (int)copyData:(AudioBufferList*)ioData requestedPackets:(UInt32)requestedPackets{
	NSData *data = nil;
	
	[_condition lock];
	{
		if(_samples.count == 0){
			[_condition wait];
		}
		//NSLog(@"_samples %d", (int)_samples.count);
		data = _samples.firstObject;
		if(data){
			[_samples removeObjectAtIndex:0];
		}
	}
	[_condition unlock];
	
	if(!data || !_running){
		NSLog(@"copyData is signaled to exit");
		return 0;
	}
	
	_processing_data = data;
	ioData->mBuffers[0].mNumberChannels = _srcFormat.mChannelsPerFrame;
	ioData->mBuffers[0].mData = (void *)_processing_data.bytes;
	ioData->mBuffers[0].mDataByteSize = (UInt32)_processing_data.length;
	
	int ret = (int)_processing_data.length / _srcFormat.mBytesPerPacket;
	return ret;
	
	//	AudioStreamBasicDescription f = *CMAudioFormatDescriptionGetStreamBasicDescription((CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer));
	//	if(f.mBitsPerChannel != _srcFormat.mBitsPerChannel || f.mChannelsPerFrame != _srcFormat.mChannelsPerFrame || f.mSampleRate != _srcFormat.mSampleRate){
	//		CFRelease(sampleBuffer);
	//		NSLog(@"Sample format changed!");
	//		[self printFormat:_srcFormat name:@"old"];
	//		[self printFormat:f name:@"new"];
	//		return -1;
	//	}
}

- (void)printFormat:(AudioStreamBasicDescription)format name:(NSString *)name{
	NSLog(@"--- begin %@", name);
	NSLog(@"format.mFormatID:         %d", format.mFormatID);
	NSLog(@"format.mFormatFlags:      %d", format.mFormatFlags);
	NSLog(@"format.mSampleRate:       %f", format.mSampleRate);
	NSLog(@"format.mBitsPerChannel:   %d", format.mBitsPerChannel);
	NSLog(@"format.mChannelsPerFrame: %d", format.mChannelsPerFrame);
	NSLog(@"format.mBytesPerFrame:    %d", format.mBytesPerFrame);
	NSLog(@"format.mFramesPerPacket:  %d", format.mFramesPerPacket);
	NSLog(@"format.mBytesPerPacket:   %d", format.mBytesPerPacket);
	NSLog(@"format.mReserved:         %d", format.mReserved);
	NSLog(@"--- end %@", name);
}

- (void)createConverter{
	/*
	 http://stackoverflow.com/questions/12252791/understanding-remote-i-o-audiostreambasicdescription-asbd
	 注意, !kLinearPCMFormatFlagIsNonInterleaved(默认是 interleaved 的)
	 mBytesPerFrame != mChannelsPerFrame * mBitsPerChannel /8
	 */
	// 似乎对 kAudioFormatMPEG4AAC, 不能指定下面的属性
	if(_srcFormat.mFormatID == kAudioFormatMPEG4AAC){
		_srcFormat.mBitsPerChannel = 0;
		_srcFormat.mBytesPerFrame = 0;
		_srcFormat.mBytesPerPacket = 0;
	}
	if(_dstFormat.mFormatID == kAudioFormatMPEG4AAC){
		_dstFormat.mBitsPerChannel = 0;
		_dstFormat.mBytesPerFrame = 0;
		_dstFormat.mBytesPerPacket = 0;
	}
	// PCM 不指定 bitrate
	if(_dstFormat.mFormatID == kAudioFormatLinearPCM){
		_bitrate = 0;
	}

//	[self printFormat:_srcFormat name:@"src"];
//	[self printFormat:_dstFormat name:@"dst"];
	
	OSStatus err;
//	AudioClassDescription *description = [self getAudioClassDescription];
//	err = AudioConverterNewSpecific(&_srcFormat,
//												&_dstFormat,
//												1, description,
//												&_converter);
	err = AudioConverterNew(&_srcFormat, &_dstFormat, &_converter);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	
	// 获取真正的 format
	UInt32 size = sizeof(_srcFormat);
	err = AudioConverterGetProperty(_converter, kAudioConverterCurrentInputStreamDescription, &size, &_srcFormat);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	size = sizeof(_dstFormat);
	err = AudioConverterGetProperty(_converter, kAudioConverterCurrentOutputStreamDescription, &size, &_dstFormat);
	if (err != 0) {
		NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		NSLog(@"line: %d, error: %@", __LINE__, error);
		return;
	}
	
	if (_bitrate != 0) {
		UInt32 bitrate = (UInt32)_bitrate;
		UInt32 size = sizeof(bitrate);
		err = AudioConverterSetProperty(_converter, kAudioConverterEncodeBitRate, size, &bitrate);
		if (err != 0) {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"line: %d, error: %@", __LINE__, error);
		}
		err = AudioConverterGetProperty(_converter, kAudioConverterEncodeBitRate, &size, &bitrate);
		if (err != 0) {
			NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
			NSLog(@"line: %d, error: %@", __LINE__, error);
		}else{
			NSLog(@"set bitrate: %d", bitrate);
		}
	}
	
	// 创建 AAC converter 的时候不能指定, 所以这里要补充回来
	if(_srcFormat.mBytesPerPacket == 0){
		_srcFormat.mBitsPerChannel = _srcFormat.mChannelsPerFrame * 8;
		_srcFormat.mBytesPerPacket = _srcFormat.mChannelsPerFrame * 2;
		_srcFormat.mBytesPerFrame = _srcFormat.mBytesPerPacket;
	}
	if(_dstFormat.mBytesPerPacket == 0){
		_dstFormat.mBitsPerChannel = _dstFormat.mChannelsPerFrame * 8;
		_dstFormat.mBytesPerPacket = _dstFormat.mChannelsPerFrame * 2;
		_dstFormat.mBytesPerFrame = _dstFormat.mBytesPerPacket;
	}
	
	[self printFormat:_srcFormat name:@"src"];
	[self printFormat:_dstFormat name:@"dst"];
}

- (AudioClassDescription *)getAudioClassDescription{
	UInt32 type = kAudioFormatMPEG4AAC;
	UInt32 encoderSpecifier = type;
	OSStatus st;
	
	UInt32 size;
	st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
									sizeof(encoderSpecifier),
									&encoderSpecifier,
									&size);
	if (st) {
		NSLog(@"error getting audio format propery info: %d", (int)(st));
		return nil;
	}
	
	unsigned int count = size / sizeof(AudioClassDescription);
	AudioClassDescription descriptions[count];
	st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
								sizeof(encoderSpecifier),
								&encoderSpecifier,
								&size,
								descriptions);
	if (st) {
		NSLog(@"error getting audio format propery: %d", (int)(st));
		return nil;
	}
	for (unsigned int i = 0; i < count; i++) {
		NSLog(@"%d %d %d", descriptions[i].mType, descriptions[i].mSubType, descriptions[i].mManufacturer);
	}
	//	for (unsigned int i = 0; i < count; i++) {
	//		UInt32 manufacturer = kAppleSoftwareAudioCodecManufacturer;
	//		if((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer)) {
	//			memcpy(&desc, &(descriptions[i]), sizeof(desc));
	//			return &desc;
	//		}
	//	}
	NSLog(@"error getting AudioClassDescription");
	return nil;
}



/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData*) adtsDataForPacketLength:(NSUInteger)packetLength {
	AudioStreamBasicDescription _format;
	int adtsLength = 7;
	char *packet = (char *)malloc(sizeof(char) * adtsLength);
	memset(packet, 0, adtsLength);
	// Variables Recycled by addADTStoPacket
	int profile = 2;  //AAC LC
	//39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
	int freqIdx = 4;  //44.1KHz
	if(_format.mSampleRate == 96000){
		freqIdx = 0;
	}else if(_format.mSampleRate == 88200){
		freqIdx = 1;
	}else if(_format.mSampleRate == 64000){
		freqIdx = 2;
	}else if(_format.mSampleRate == 48000){
		freqIdx = 3;
	}else if(_format.mSampleRate == 44100){
		freqIdx = 4;
	}else if(_format.mSampleRate == 32000){
		freqIdx = 5;
	}else if(_format.mSampleRate == 22050){
		freqIdx = 6;
	}else if(_format.mSampleRate == 16000){
		freqIdx = 7;
	}else if(_format.mSampleRate == 12000){
		freqIdx = 8;
	}else if(_format.mSampleRate == 11025){
		freqIdx = 9;
	}else if(_format.mSampleRate == 8000){
		freqIdx = 10;
	}else if(_format.mSampleRate == 7350){
		freqIdx = 11;
	}
	int chanCfg = _format.mChannelsPerFrame;  //MPEG-4 Audio Channel Configuration.
	UInt16 fullLength = adtsLength + packetLength; // 13 bit
	// fill in ADTS data
	packet[0] |= (char)0xFF; // 8 bits syncword
	//
	packet[1] |= (char)0xf0; // 4 bits syncword
	packet[1] |= 0 << 3;     // 1 bits ID, '0': MPEG-4, '1': MPEG-2
	packet[1] |= 0 << 2;     // 2 bits layer, always '00'
	packet[1] |= 1 << 0;     // 1 bit protection_absent
	//
	packet[2] |= (profile - 1) << 6;     // 2 bits profile
	packet[2] |= (freqIdx & 0xf) << 2;   // 4 bits sample index
	packet[2] |= 0 << 1;                 // 1 bits private
	packet[2] |= (chanCfg & 0x4) >> 2;   // 1 bits channel
	//
	packet[3] |= (chanCfg & 0x3) << 6;      // 2 bits channel
	packet[3] |= 0;                         // 1 bits oringal
	packet[3] |= 0;                         // 1 bits home
	packet[3] |= 0;                         // 1 bits copyright
	packet[3] |= 0;                         // 1 bits copyright
	packet[3] |= (fullLength >> 11) & 0x3;  // 2 bits length
	//
	packet[4] |= (fullLength >> 3)  & 0xff; // 8 bits length
	packet[5] |= (fullLength & 0x7) << 5;   // 3 bits length
	packet[5] |= 0x1f;                      // 5 bits fullness
	//
	packet[6] |= 0xfc; // 6 bits fullness + 2 bits
	NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
	return data;
}


@end
