//
//  VivaPlaybackManager.h
//  Viva
//
//  Created by Daniel Kennett on 3/30/11.
//  Copyright 2011 Spotify. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "VivaPlaybackContext.h"
#import <CocoaLibSpotify/CocoaLibSpotify.h>
#import "CoCA.h"

@interface VivaPlaybackManager : NSObject <CoCAAudioUnitRenderDelegate, SPSpotifySessionPlaybackDelegate> {
@private
    id <VivaPlaybackContext> playbackContext;
	SPSpotifyTrack *currentTrack;
	NSMutableData *audioBuffer;
	CoCAAudioUnit *audioUnit;
	NSTimeInterval currentTrackPosition;
	SPSpotifySession *playbackSession;
}

-(id)initWithPlaybackSession:(SPSpotifySession *)aSession;

@property (readonly, retain) id <VivaPlaybackContext> playbackContext;
@property (readwrite) NSTimeInterval currentTrackPosition;
@property (readonly, retain) SPSpotifyTrack *currentTrack;
@property (readonly, retain) SPSpotifySession *playbackSession;

-(void)seekToTrackPosition:(NSTimeInterval)newPosition;

@end