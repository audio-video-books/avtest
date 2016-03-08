//
//  AppDelegate.m
//  VideoTest
//
//  Created by ideawu on 12/11/15.
//  Copyright © 2015 ideawu. All rights reserved.
//

#import "AppDelegate.h"
#import "PlayerController.h"
#import "RecorderController.h"
#import "TestController.h"

@interface AppDelegate (){
	PlayerController *_player;
	RecorderController *_recorder;
	TestController *_test;
}

@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	NSLog(@"NSTemporaryDirectory: %@", NSTemporaryDirectory());
	// Insert code here to initialize your application
//	_player = [[PlayerController alloc] initWithWindowNibName:@"PlayerController"];
//	[_player showWindow:self];

//	_recorder = [[RecorderController alloc] initWithWindowNibName:@"RecorderController"];
//	[_recorder showWindow:self];
	
	_test = [[TestController alloc] initWithWindowNibName:@"TestController"];
	[_test showWindow:self];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender{
	return YES;
}

@end
