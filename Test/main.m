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

#define QUIT() do{ \
		NSLog(@"sleep"); \
		sleep(15); \
		test = nil; \
		NSLog(@"quit"); \
	}while(0)

int main(int argc, const char * argv[]) {
	int flag = 0;

	if(flag == 0){
		return NSApplicationMain(argc, argv);
	}

	int count = 0;
	if(flag == ++count){
		TestRecorder *test = [[TestRecorder alloc] init];
		QUIT();
	}
	if(flag == ++count){
		TestVideo *test = [[TestVideo alloc] init];
		QUIT();
	}
	
}
