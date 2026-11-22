#import "audio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>

extern void *tone_create(void);
extern void tone_destroy(void *tone);
extern void tone_render(void *tone, float *buffer, size_t frames, double rate);

enum AudioStartResult {
    AudioStarted = 0,
    AudioMissingSoundbar = 1,
    AudioUnavailable = 2,
};

typedef struct {
    void *tone;
    Float64 rate;
} RenderContext;

static AudioUnit outputUnit;
static AudioDeviceID activeDevice = kAudioObjectUnknown;
static RenderContext renderContext;
static NSString *selectedOutputUID;
static dispatch_block_t routeChanged;
static AudioObjectPropertyListenerBlock systemListener, deviceListener;
static uint64_t streamGeneration;

static const AudioObjectPropertyAddress systemProperties[] = {
    {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
};

static const AudioObjectPropertyAddress deviceProperties[] = {
    {kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    {kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
    {kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain},
};

static NSString *deviceString(AudioDeviceID device, AudioObjectPropertySelector selector) {
    if (device == kAudioObjectUnknown) return nil;
    AudioObjectPropertyAddress property = {selector, kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain};
    CFStringRef string = NULL;
    UInt32 size = sizeof(string);
    if (AudioObjectGetPropertyData(device, &property, 0, NULL, &size, &string) != noErr) return nil;
    return CFBridgingRelease(string);
}

static BOOL deviceHasOutput(AudioDeviceID device) {
    UInt32 size = 0;
    return AudioObjectGetPropertyDataSize(device, &deviceProperties[2], 0, NULL, &size) == noErr
        && size >= sizeof(AudioStreamID);
}

static AudioDeviceID targetDevice(void) {
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    OSStatus result;
    if (selectedOutputUID) {
        AudioObjectPropertyAddress property = {kAudioHardwarePropertyTranslateUIDToDevice,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        CFStringRef uid = (__bridge CFStringRef)selectedOutputUID;
        result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &property,
            sizeof(uid), &uid, &size, &device);
    } else {
        result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &systemProperties[0],
            0, NULL, &size, &device);
    }
    if (result != noErr || device == kAudioObjectUnknown) return kAudioObjectUnknown;

    UInt32 alive = 0;
    size = sizeof(alive);
    result = AudioObjectGetPropertyData(device, &deviceProperties[0], 0, NULL, &size, &alive);
    return result == noErr && alive && deviceHasOutput(device) ? device : kAudioObjectUnknown;
}

NSDictionary<NSString *, NSString *> *audio_output_devices(void) {
    NSMutableDictionary<NSString *, NSString *> *outputs = [NSMutableDictionary dictionary];
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &systemProperties[1],
        0, NULL, &size) != noErr || size == 0) return outputs;
    NSMutableData *storage = [NSMutableData dataWithLength:size];
    AudioDeviceID *devices = storage.mutableBytes;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &systemProperties[1],
        0, NULL, &size, devices) != noErr) return outputs;
    for (NSUInteger index = 0; index < size / sizeof(*devices); index++) {
        AudioDeviceID device = devices[index];
        if (!deviceHasOutput(device)) continue;
        NSString *uid = deviceString(device, kAudioDevicePropertyDeviceUID);
        NSString *name = deviceString(device, kAudioObjectPropertyName);
        if (uid.length && name.length) outputs[uid] = name;
    }
    return outputs;
}

NSString *audio_output_name(void) {
    AudioDeviceID device = outputUnit ? activeDevice : targetDevice();
    return deviceString(device, kAudioObjectPropertyName);
}

void audio_select_output(NSString *uid) {
    selectedOutputUID = [uid copy];
}

static void listen(AudioObjectID object, const AudioObjectPropertyAddress *properties,
                   size_t count, AudioObjectPropertyListenerBlock listener, BOOL add) {
    for (size_t index = 0; index < count; index++) {
        const AudioObjectPropertyAddress *property = &properties[index];
        if (add) {
            OSStatus result = AudioObjectAddPropertyListenerBlock(object, property,
                dispatch_get_main_queue(), listener);
            if (result != noErr) NSLog(@"Could not monitor audio property %u: %d",
                (unsigned int)property->mSelector, (int)result);
        } else {
            AudioObjectRemovePropertyListenerBlock(object, property, dispatch_get_main_queue(), listener);
        }
    }
}

void audio_observe_route_changes(dispatch_block_t handler) {
    routeChanged = [handler copy];
    systemListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        if (routeChanged && (!outputUnit || targetDevice() != activeDevice)) routeChanged();
    };
    listen(kAudioObjectSystemObject, systemProperties,
        sizeof(systemProperties) / sizeof(*systemProperties), systemListener, YES);
}

void audio_remove_route_observer(void) {
    routeChanged = nil;
    if (systemListener) {
        listen(kAudioObjectSystemObject, systemProperties,
            sizeof(systemProperties) / sizeof(*systemProperties), systemListener, NO);
        systemListener = nil;
    }
}

static OSStatus renderTone(void *context, AudioUnitRenderActionFlags *flags,
                           const AudioTimeStamp *time, UInt32 bus, UInt32 frames,
                           AudioBufferList *buffers) {
    if (frames == 0) return noErr;
    if (!buffers || buffers->mNumberBuffers == 0) return kAudio_ParamError;

    size_t bytes = (size_t)frames * sizeof(float);
    for (UInt32 channel = 0; channel < buffers->mNumberBuffers; channel++) {
        AudioBuffer buffer = buffers->mBuffers[channel];
        if (!buffer.mData || buffer.mDataByteSize < bytes) return kAudio_ParamError;
    }
    RenderContext *render = context;
    float *first = buffers->mBuffers[0].mData;
    tone_render(render->tone, first, frames, render->rate);
    for (UInt32 channel = 1; channel < buffers->mNumberBuffers; channel++) {
        memcpy(buffers->mBuffers[channel].mData, first, bytes);
    }
    return noErr;
}

void stop_audio(void) {
    if (!outputUnit) return;
    streamGeneration++;
    if (deviceListener) {
        listen(activeDevice, deviceProperties, sizeof(deviceProperties) / sizeof(*deviceProperties),
            deviceListener, NO);
        deviceListener = nil;
    }
    AudioOutputUnitStop(outputUnit);
    AudioUnitUninitialize(outputUnit);
    AudioComponentInstanceDispose(outputUnit);
    outputUnit = NULL;
    activeDevice = kAudioObjectUnknown;
    if (renderContext.tone) tone_destroy(renderContext.tone);
    renderContext = (RenderContext){0};
}

int start_audio(void) {
    AudioDeviceID device = targetDevice();
    if (device == kAudioObjectUnknown) return selectedOutputUID ? AudioMissingSoundbar : AudioUnavailable;

    // The HAL output unit binds to this device even when the system default changes.
    AudioComponentDescription description = {
        .componentType = kAudioUnitType_Output,
        .componentSubType = kAudioUnitSubType_HALOutput,
        .componentManufacturer = kAudioUnitManufacturer_Apple,
    };
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    if (!component) return AudioUnavailable;

    OSStatus result = AudioComponentInstanceNew(component, &outputUnit);
    if (result != noErr) goto failed;
    UInt32 enabled = 1;
    result = AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_EnableIO,
        kAudioUnitScope_Output, 0, &enabled, sizeof(enabled));
    if (result != noErr) goto failed;
    result = AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global, 0, &device, sizeof(device));
    if (result != noErr) goto failed;

    AudioStreamBasicDescription hardwareFormat = {0};
    UInt32 size = sizeof(hardwareFormat);
    result = AudioUnitGetProperty(outputUnit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Output, 0, &hardwareFormat, &size);
    if (result != noErr) goto failed;
    if (!isfinite(hardwareFormat.mSampleRate) || hardwareFormat.mSampleRate <= 0
        || hardwareFormat.mChannelsPerFrame == 0) {
        result = kAudioUnitErr_FormatNotSupported;
        goto failed;
    }

    AudioStreamBasicDescription format = {
        .mSampleRate = hardwareFormat.mSampleRate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
        .mBytesPerPacket = sizeof(float),
        .mFramesPerPacket = 1,
        .mBytesPerFrame = sizeof(float),
        .mChannelsPerFrame = hardwareFormat.mChannelsPerFrame,
        .mBitsPerChannel = 8 * sizeof(float),
    };
    result = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_StreamFormat,
        kAudioUnitScope_Input, 0, &format, sizeof(format));
    if (result != noErr) goto failed;

    renderContext = (RenderContext){.tone = tone_create(), .rate = format.mSampleRate};
    AURenderCallbackStruct callback = {.inputProc = renderTone, .inputProcRefCon = &renderContext};
    result = AudioUnitSetProperty(outputUnit, kAudioUnitProperty_SetRenderCallback,
        kAudioUnitScope_Input, 0, &callback, sizeof(callback));
    if (result != noErr) goto failed;
    result = AudioUnitInitialize(outputUnit);
    if (result != noErr) goto failed;
    result = AudioOutputUnitStart(outputUnit);
    if (result != noErr) goto failed;

    // Rust enables audible samples only after this device check succeeds.
    AudioDeviceID actualDevice = kAudioObjectUnknown;
    size = sizeof(actualDevice);
    result = AudioUnitGetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global, 0, &actualDevice, &size);
    if (result != noErr) goto failed;
    if (actualDevice != device || targetDevice() != device) {
        stop_audio();
        return selectedOutputUID ? AudioMissingSoundbar : AudioUnavailable;
    }
    activeDevice = device;
    uint64_t generation = streamGeneration;
    deviceListener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        if (routeChanged && generation == streamGeneration) routeChanged();
    };
    listen(device, deviceProperties, sizeof(deviceProperties) / sizeof(*deviceProperties),
        deviceListener, YES);
    return AudioStarted;

failed:
    NSLog(@"Could not start audio output (Core Audio error %d)", (int)result);
    stop_audio();
    if (selectedOutputUID && targetDevice() == kAudioObjectUnknown) return AudioMissingSoundbar;
    return AudioUnavailable;
}
