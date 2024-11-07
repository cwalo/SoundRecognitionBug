//
//  AudioSystem.m
//  SoundRecognitionBug
//
//  Created by Mark Gill on 10/4/24.
//

// Heavily influenced by
// https://atastypixel.com/using-remoteio-audio-unit/

#import "AudioSystem.h"
#import <AudioUnit/AudioUnit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#include <memory>
#include <set>
#include "CircularBuffer.h"

#define kOutputBus 0
#define kInputBus 1
#define kMono 1

static std::unique_ptr<CircularBuffer<SInt32>> buffer;
static AudioBufferList *inputBufferList;

OSStatus recordCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
        UInt32 inNumberFrames, AudioBufferList *ioData);

OSStatus playbackCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags,
        const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber,
        UInt32 inNumberFrames, AudioBufferList *ioData);

@interface AudioSystem() {
}

@property(nonatomic,readwrite) AudioUnit audioUnit;
@property(nonatomic) double sampleRate;
@property(nonatomic) UInt32 hardwareBufferSize;

@end

@implementation AudioSystem

- (void) setup {
    self.sampleRate = [AVAudioSession sharedInstance].sampleRate;
    self.hardwareBufferSize = std::ceil(self.sampleRate/[AVAudioSession sharedInstance].IOBufferDuration);
    [self configureAudioSession];
    
    buffer = std::make_unique<CircularBuffer<SInt32>>(self.sampleRate);
    inputBufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    inputBufferList->mNumberBuffers = 1;
    inputBufferList->mBuffers[0].mNumberChannels = 1;
    inputBufferList->mBuffers[0].mDataByteSize = 4096*sizeof(SInt32);
    inputBufferList->mBuffers[0].mData = malloc(4096*sizeof(SInt32));
    
    AudioComponentDescription acd = [self audioComponentDescription];
    AudioComponent comp = AudioComponentFindNext( NULL, &acd );
    
    OSStatus err;
    err = AudioComponentInstanceNew( comp, &_audioUnit );
    
    UInt32 one = [AVAudioSession sharedInstance].inputAvailable;
    err = AudioUnitSetProperty( _audioUnit, 
                               kAudioOutputUnitProperty_EnableIO,
                               kAudioUnitScope_Input,
                               1,
                               &one,
                               sizeof(one));
    
    [self configureCallbacks];
    [self configureStreamDescriptions];
}

- (void) start {
    [self setup];
    AudioOutputUnitStart(_audioUnit);
    [self printStreamDescriptions];
}

- (void) stop {
}

- (AudioComponentDescription) audioComponentDescription {
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    return desc;
}

- (OSStatus) configureAudioSession {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                     withOptions:0
                                           error:&error];

    auto preferred_buffer_duration = 256 / [AVAudioSession sharedInstance].sampleRate;
    NSLog(@"Requested IOBufferDuration: %f", preferred_buffer_duration);
    
    if (![[AVAudioSession sharedInstance] setPreferredIOBufferDuration:preferred_buffer_duration error:&error]) {
        NSLog(@"Failed to set preferred buffer size");
    }
    
    [[AVAudioSession sharedInstance] setActive:true error:&error];

    if (error) {
        NSLog(@"AVAudioSession error: %@", error);
    }
    
    auto io_buffer_duration = [AVAudioSession sharedInstance].IOBufferDuration;
    NSLog(@"Actual IOBufferDuration: %f", io_buffer_duration);
    
    return noErr;
}

- (OSStatus) configureCallbacks {
    OSStatus err = noErr;
    AURenderCallbackStruct callbackStruct; // set render proc, the internal audio callback
    callbackStruct.inputProc = recordCallback; // set the callback to our local callback
    callbackStruct.inputProcRefCon = (__bridge void*)self; // pass the audio unit
    err = AudioUnitSetProperty(_audioUnit,
                               kAudioOutputUnitProperty_SetInputCallback,
                               kAudioUnitScope_Input,
                               kInputBus,
                               &callbackStruct,
                               sizeof(callbackStruct));
    
    callbackStruct.inputProc = playbackCallback;
    err = AudioUnitSetProperty(_audioUnit,
                               kAudioUnitProperty_SetRenderCallback,
                               kAudioUnitScope_Output,
                               kOutputBus,
                               &callbackStruct,
                               sizeof(callbackStruct));
    
    return err;
}

- (OSStatus) configureStreamDescriptions {
    OSStatus err = noErr;
    AudioStreamBasicDescription asbd;
    UInt32 size = sizeof(asbd);
    err = AudioUnitGetProperty(_audioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input,
                               0,
                               &asbd,
                               &size);
    
    asbd.mSampleRate = self.sampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mFramesPerPacket = 1;
    asbd.mChannelsPerFrame = kMono;
    asbd.mBitsPerChannel = 32;
    asbd.mBytesPerPacket = 4;
    asbd.mBytesPerFrame = 4;
    
    err = AudioUnitSetProperty(_audioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input,
                               0,
                               &asbd,
                               sizeof(asbd));
    err = AudioUnitSetProperty(_audioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Output,
                               1,
                               &asbd,
                               sizeof(asbd));
    
    return err;
}

- (void)printStreamDescriptions {
    OSStatus err;
    AudioStreamBasicDescription asbd;
    UInt32 size = sizeof(asbd);
    
    err = AudioUnitGetProperty(_audioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Input,
                               0,
                               &asbd,
                               &size);
    NSLog(@"AU input sample rate: %f", asbd.mSampleRate);
    err = AudioUnitGetProperty(_audioUnit,
                               kAudioUnitProperty_StreamFormat,
                               kAudioUnitScope_Output,
                               1,
                               &asbd,
                               &size);
    NSLog(@"AU output sample rate: %f", asbd.mSampleRate);
    
    NSLog(@"hardware sample rate: %f", [AVAudioSession sharedInstance].sampleRate);
    
    auto system_buffer_size = std::ceil([AVAudioSession sharedInstance].IOBufferDuration * [AVAudioSession sharedInstance].sampleRate);
    NSLog(@"hardware buffer size: %f", system_buffer_size);
}

- (void) checkSetContains:(std::set<UInt32> &)set 
                    value:(UInt32)value
                   source:(NSString *)source{
    if (!set.count(value)) {
        set.insert(value);
        std::string framesStr;
        for (auto &value : set) {
            framesStr += " " + std::to_string(value);
        }
        NSLog(@"updated %@ frame counts: %@", source, [NSString stringWithUTF8String:framesStr.c_str()]);
    }
}

@end


static unsigned recordCount=0;
static unsigned playbackCount=0;
static float sinTime = 0.0;
static bool sinEnabled = false;
static bool mutesOutput = false; // set to true to observe issue without headset
static std::vector<std::set<UInt32>> frameCounts(2);

OSStatus recordCallback(void *inRef,
                        AudioUnitRenderActionFlags *ioActionFlags,
                        const AudioTimeStamp *inTimeStamp,
                        UInt32 inBusNumber,
                        UInt32 inNumberFrames, 
                        AudioBufferList *ioData) {
    AudioSystem *audioSystem = (__bridge AudioSystem*)inRef;
    inputBufferList->mBuffers[0].mDataByteSize = inNumberFrames*sizeof(SInt32);
    OSStatus err = AudioUnitRender( audioSystem.audioUnit, ioActionFlags, inTimeStamp, 1, inNumberFrames, inputBufferList );
    if( err ) {
        NSLog(@"mic read error!");
        return err;
    }
    
    SInt32 sample;
    SInt32 *inBuffer = (SInt32 *) inputBufferList->mBuffers[0].mData;
    for (int i = 0; i < inNumberFrames; i++) {
        sample = inBuffer[i];
        buffer->push_back(sample);
    }
    
    [audioSystem checkSetContains:frameCounts[0] value:inNumberFrames source:@"record"];
    
    recordCount++;
    return noErr;
}

OSStatus playbackCallback(void *inRef,
                          AudioUnitRenderActionFlags *ioActionFlags,
                          const AudioTimeStamp *inTimeStamp,
                          UInt32 inBusNumber,
                          UInt32 inNumberFrames, 
                          AudioBufferList *ioData) {
    AudioSystem *audioSystem = (__bridge AudioSystem*)inRef;
    SInt32 *left  = (SInt32 *) ioData->mBuffers[0].mData;
    static const float dt = 1.0/audioSystem.sampleRate;
    static const float floatToInt = (float)(1 << 24);
    
    for (int i = 0; i < inNumberFrames; i++) {
        if (sinEnabled) {
            auto result = sin(2.0*M_PI*400.0*sinTime);
            sinTime += dt;
            left[i] = (SInt32) (result * floatToInt);
        } else {
            left[i] = 0.0;
        }
        
        auto micSample = buffer->pop_front();
        if (mutesOutput) {
            left[i] = 0.0;
        } else {
            left[i] += (SInt32) micSample;
        }
    }
    
    playbackCount++;
    if (playbackCount % 500 == 0) {
        auto system_buffer_size = std::ceil([AVAudioSession sharedInstance].IOBufferDuration * [AVAudioSession sharedInstance].sampleRate);
        NSLog(@"hardware buffer size: %f", system_buffer_size);
        // callback rates are equal
        NSLog(@"playbackCount: %d recordCount: %d", playbackCount, recordCount);
    }
    
    [audioSystem checkSetContains:frameCounts[1] value:inNumberFrames source:@"playback"];
    return noErr;
}
