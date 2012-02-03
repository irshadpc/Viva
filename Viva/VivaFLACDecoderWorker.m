//
//  VivaFLACDecoder.m
//  Viva
//
//  Created by Daniel Kennett on 03/02/2012.
//  For license information, see LICENSE.markdown
//

#import "VivaFLACDecoderWorker.h"
#import <flac/stream_decoder.h>
#import <CocoaLibSpotify/CocoaLibSpotify.h>

static FLAC__StreamDecoderWriteStatus FLAC_write_callback(const FLAC__StreamDecoder *decoder, const FLAC__Frame *frame, const FLAC__int32 * const buffer[], void *client_data);
static void FLAC_metadata_callback(const FLAC__StreamDecoder *decoder, const FLAC__StreamMetadata *metadata, void *client_data);
static void FLAC_error_callback(const FLAC__StreamDecoder *decoder, FLAC__StreamDecoderErrorStatus status, void *client_data);


@implementation VivaFLACDecoderWorker {
	FLAC__uint64 total_samples;
	NSUInteger sample_rate;
	NSUInteger channels;
	NSUInteger bits_per_sample;
	sp_audioformat output_format;
}

@synthesize delegate;
@synthesize cancelled;
@synthesize playing;

-(void)decodeLocalFile:(LocalFile *)file fromPosition:(NSTimeInterval)startTime {
	
	[self performSelectorInBackground:@selector(decodeAssetOnThreadWithProperties:)
						   withObject:[NSDictionary dictionaryWithObjectsAndKeys:
									   file.path, @"path",
									   [NSNumber numberWithDouble:startTime], @"start", nil]];
	
}

-(void)decodeAssetOnThreadWithProperties:(NSDictionary *)properties {
	
	@autoreleasepool {
		
		NSString *path = [properties valueForKey:@"path"];
		NSTimeInterval startTime = [[properties valueForKey:@"start"] doubleValue];
		
		FLAC__StreamDecoder *decoder = FLAC__stream_decoder_new();
		
		if (decoder == NULL) {
			NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"Couldn't init decoder!");
			[self performSelectorOnMainThread:@selector(endPlaybackThread) withObject:nil waitUntilDone:NO];
			return;
		}
		
		const char *path_cstr = [path UTF8String];
		
		FLAC__StreamDecoderInitStatus init_status = FLAC__stream_decoder_init_file(decoder,
																				   path_cstr,
																				   FLAC_write_callback,
																				   FLAC_metadata_callback,
																				   FLAC_error_callback,
																				   (__bridge void *)self);
		
		if(init_status != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
			NSLog(@"[%@ %@]: %@ %s", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"Couldn't init decoder:", FLAC__StreamDecoderInitStatusString[init_status]);
			[self performSelectorOnMainThread:@selector(endPlaybackThread) withObject:nil waitUntilDone:NO];
			return;
		}
		
		// Read metadata
		FLAC__bool success = FLAC__stream_decoder_process_until_end_of_metadata(decoder);
		if (!success) {
			NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"Couldn't read metadata");
			[self performSelectorOnMainThread:@selector(endPlaybackThread) withObject:nil waitUntilDone:NO];
			return;
		}
		
		// Have metadata
		if (startTime > 0.0) {
			// Seek
			FLAC__stream_decoder_seek_absolute(decoder, (FLAC__int64)sample_rate * startTime);
		}

		success = FLAC__stream_decoder_process_until_end_of_stream(decoder);
		fprintf(stderr, "decoding: %s\n", success ? "succeeded" : "FAILED");
		fprintf(stderr, "   state: %s\n", FLAC__StreamDecoderStateString[FLAC__stream_decoder_get_state(decoder)]);

		FLAC__stream_decoder_delete(decoder);
		decoder = NULL;
		
		[self performSelectorOnMainThread:@selector(endPlaybackThread) withObject:nil waitUntilDone:NO];
	}
}

-(void)endPlaybackThread {
	[self.delegate workerDidCompleteAudioPlayback:self];
}

static FLAC__StreamDecoderWriteStatus FLAC_write_callback(const FLAC__StreamDecoder *decoder, const FLAC__Frame *frame, const FLAC__int32 * const buffer[], void *client_data) {
	
	VivaFLACDecoderWorker *self = (__bridge VivaFLACDecoderWorker *)client_data;
	
	if (self.cancelled) return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
	
	AudioStreamBasicDescription flacInputFormat;
    flacInputFormat.mSampleRate = self->sample_rate;
    flacInputFormat.mFormatID = kAudioFormatLinearPCM;
    flacInputFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
    flacInputFormat.mBytesPerPacket = (UInt32)(self->channels * (self->bits_per_sample / 8));
    flacInputFormat.mFramesPerPacket = 1;
    flacInputFormat.mBytesPerFrame = flacInputFormat.mBytesPerPacket;
    flacInputFormat.mChannelsPerFrame = (UInt32)self->channels;
    flacInputFormat.mBitsPerChannel = (UInt32)self->bits_per_sample;
    flacInputFormat.mReserved = 0;
	
	NSUInteger sample_size = self->bits_per_sample / 8;
	NSUInteger total_sample_count = frame->header.blocksize * self->channels;
	
	int16_t interleaved_data[total_sample_count];
	
	for(size_t i = 0; i < frame->header.blocksize; i++) {
		
		// TODO: Losing audio information here (decoder give us 32-bit samples)
		int16_t leftSample = (int16_t)buffer[0][i];
		int16_t rightSample = (int16_t)buffer[1][i];
		
		interleaved_data[i * 2] = leftSample;
		interleaved_data[(i * 2) + 1] = rightSample; 
	}
	
	while (!self.isPlaying && !self.cancelled) {
		// Don't push audio data if we're paused.
		[NSThread sleepForTimeInterval:0.1];
	}
	
	while (!self.cancelled && ([self.delegate worker:self
							shouldDeliverAudioFrames:(const void *)&interleaved_data
											 ofCount:frame->header.blocksize
											  format:flacInputFormat] == 0)) {
		[NSThread sleepForTimeInterval:0.1];
	}
	
	return self.cancelled ? FLAC__STREAM_DECODER_WRITE_STATUS_ABORT : FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void FLAC_metadata_callback(const FLAC__StreamDecoder *decoder, const FLAC__StreamMetadata *metadata, void *client_data) {
	
	VivaFLACDecoderWorker *self = (__bridge VivaFLACDecoderWorker *)client_data;
	
	/* print some stats */
	if(metadata->type == FLAC__METADATA_TYPE_STREAMINFO) {
		/* save for later */
		self->total_samples = metadata->data.stream_info.total_samples;
		self->sample_rate = metadata->data.stream_info.sample_rate;
		self->channels = metadata->data.stream_info.channels;
		self->bits_per_sample = metadata->data.stream_info.bits_per_sample;
		
		self->output_format.channels = (int)self->channels;
		self->output_format.sample_rate = (int)self->sample_rate;
		self->output_format.sample_type = SP_SAMPLETYPE_INT16_NATIVE_ENDIAN;
		
		fprintf(stderr, "sample rate    : %lu Hz\n", self->sample_rate);
		fprintf(stderr, "channels       : %lu\n", self->channels);
		fprintf(stderr, "bits per sample: %lu\n", self->bits_per_sample);
		fprintf(stderr, "total samples  : %llu\n", self->total_samples);
	}
}

static void FLAC_error_callback(const FLAC__StreamDecoder *decoder, FLAC__StreamDecoderErrorStatus status, void *client_data) {
	fprintf(stderr, "Got error callback: %s\n", FLAC__StreamDecoderErrorStatusString[status]);
}


@end