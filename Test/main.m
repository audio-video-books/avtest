//
//  main.m
//  Test
//
//  Created by ideawu on 3/1/16.
//  Copyright © 2016 ideawu. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TestAudio.h"
#import "TestVideo.h"
#import "TestRecorder.h"
#import "MovieCaptureFile.h"

#define QUIT() do{ \
		log_debug(@"sleep"); \
		sleep(15); \
		test = nil; \
		log_debug(@"quit"); \
	}while(0)

int main(int argc, const char * argv[]) {
	int count = 0;
	int flag = 0;

	if(flag == count++){
		return NSApplicationMain(argc, argv);
	}
	
	if(flag == count++){
		TestAudio *test = [[TestAudio alloc] init];
		QUIT();
	}
	if(flag == count++){
		TestRecorder *test = [[TestRecorder alloc] init];
		QUIT();
	}
	if(flag == count++){
		NSString *file = [NSHomeDirectory() stringByAppendingFormat:@"/Downloads/capture.mp4"];
		MovieCaptureFile *movie = [[MovieCaptureFile alloc] init];
		movie.filename = file;
		//movie.width = 360;
		[movie start];
		sleep(5);
		[movie stop];
		sleep(2);
		log_debug(@"quit");
	}
	
	return 0;
}
