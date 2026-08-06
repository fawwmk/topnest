#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFunction)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetPlayingFunction)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetPIDFunction)(dispatch_queue_t, void (^)(int));
typedef CFTypeRef (*MRGetLocalOriginFunction)(void);
typedef void (*MRRegisterFunction)(dispatch_queue_t);
typedef Boolean (*MRSendCommandFunction)(NSInteger, CFDictionaryRef);
typedef Boolean (*MRSendCommandToAppFunction)(
    NSInteger,
    CFDictionaryRef,
    CFTypeRef,
    CFStringRef,
    NSInteger,
    dispatch_queue_t,
    void (^)(NSInteger)
);
typedef void (*MRSetElapsedTimeFunction)(double);

static void *mediaRemoteHandle;
static dispatch_queue_t mediaQueue;
static MRGetInfoFunction getNowPlayingInfo;
static MRGetPlayingFunction getApplicationIsPlaying;
static MRGetPIDFunction getApplicationPID;
static MRGetLocalOriginFunction getLocalOrigin;
static MRRegisterFunction registerForNotifications;
static MRSendCommandFunction sendCommand;
static MRSendCommandToAppFunction sendCommandToApp;
static MRSetElapsedTimeFunction setElapsedTime;
static NSMutableArray *notificationTokens;

static NSString *StringSymbol(const char *name, NSString *fallback) {
    CFStringRef *value = mediaRemoteHandle ? dlsym(mediaRemoteHandle, name) : NULL;
    return value && *value ? (__bridge NSString *)*value : fallback;
}

static id InfoValue(NSDictionary *info, const char *symbol, NSString *fallback) {
    return info[StringSymbol(symbol, fallback)];
}

static void WriteJSON(NSDictionary *object) {
    @autoreleasepool {
        if (![NSJSONSerialization isValidJSONObject:object]) {
            return;
        }
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
        if (!data || error) {
            return;
        }
        NSMutableData *line = [data mutableCopy];
        uint8_t newline = '\n';
        [line appendBytes:&newline length:1];
        NSFileHandle *standardOutput = [NSFileHandle fileHandleWithStandardOutput];
        @synchronized(standardOutput) {
            [standardOutput writeData:line];
        }
    }
}

static void WriteError(NSString *message) {
    WriteJSON(@{
        @"type": @"error",
        @"message": message ?: @"MediaRemote is unavailable"
    });
}

static void EmitState(NSDictionary *info, BOOL playing, int pid) {
    @autoreleasepool {
        NSString *title = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoTitle",
            @"kMRMediaRemoteNowPlayingInfoTitle"
        );
        NSString *artist = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoArtist",
            @"kMRMediaRemoteNowPlayingInfoArtist"
        );
        NSString *album = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoAlbum",
            @"kMRMediaRemoteNowPlayingInfoAlbum"
        );
        NSNumber *duration = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoDuration",
            @"kMRMediaRemoteNowPlayingInfoDuration"
        );
        NSNumber *elapsed = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoElapsedTime",
            @"kMRMediaRemoteNowPlayingInfoElapsedTime"
        );
        NSNumber *rate = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate",
            @"kMRMediaRemoteNowPlayingInfoPlaybackRate"
        );
        NSData *artwork = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoArtworkData",
            @"kMRMediaRemoteNowPlayingInfoArtworkData"
        );
        NSString *contentIdentifier = InfoValue(
            info,
            "kMRMediaRemoteNowPlayingInfoExternalContentIdentifier",
            @"kMRMediaRemoteNowPlayingInfoExternalContentIdentifier"
        );
        if (![contentIdentifier isKindOfClass:NSString.class]
            || contentIdentifier.length == 0) {
            contentIdentifier = InfoValue(
                info,
                "kMRMediaRemoteNowPlayingInfoContentItemIdentifier",
                @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"
            );
        }

        NSRunningApplication *application = pid > 0
            ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid]
            : nil;
        NSString *source = application.localizedName ?: @"";
        NSString *sourceBundleIdentifier = application.bundleIdentifier ?: @"";

        NSMutableDictionary *payload = [@{
            @"type": @"state",
            @"title": [title isKindOfClass:NSString.class] ? title : @"",
            @"artist": [artist isKindOfClass:NSString.class] ? artist : @"",
            @"album": [album isKindOfClass:NSString.class] ? album : @"",
            @"source": source,
            @"sourceBundleIdentifier": sourceBundleIdentifier,
            @"duration": [duration isKindOfClass:NSNumber.class] ? duration : @0,
            @"elapsed": [elapsed isKindOfClass:NSNumber.class] ? elapsed : @0,
            @"playbackRate": [rate isKindOfClass:NSNumber.class] ? rate : @(playing ? 1 : 0),
            @"isPlaying": @(playing)
        } mutableCopy];
        if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
            payload[@"artworkBase64"] = [artwork base64EncodedStringWithOptions:0];
        }
        if ([contentIdentifier isKindOfClass:NSString.class]
            && contentIdentifier.length > 0) {
            payload[@"contentIdentifier"] = contentIdentifier;
        }
        WriteJSON(payload);
    }
}

static void RefreshState(void) {
    if (!getNowPlayingInfo) {
        WriteError(@"MediaRemote symbols are unavailable");
        return;
    }
    getNowPlayingInfo(mediaQueue, ^(CFDictionaryRef rawInfo) {
        NSDictionary *info = rawInfo ? [(__bridge NSDictionary *)rawInfo copy] : @{};
        if (!getApplicationIsPlaying) {
            EmitState(info, NO, 0);
            return;
        }
        getApplicationIsPlaying(mediaQueue, ^(Boolean playing) {
            if (!getApplicationPID) {
                EmitState(info, playing, 0);
                return;
            }
            getApplicationPID(mediaQueue, ^(int pid) {
                EmitState(info, playing, pid);
            });
        });
    });
}

static void ScheduleRefresh(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
        mediaQueue,
        ^{ RefreshState(); }
    );
}

static void HandleCommand(NSDictionary *payload) {
    NSString *command = payload[@"command"];
    if (![command isKindOfClass:NSString.class]) {
        return;
    }
    if ([command isEqualToString:@"seek"]) {
        NSNumber *value = payload[@"value"];
        if (setElapsedTime && [value isKindOfClass:NSNumber.class]) {
            setElapsedTime(MAX(0, value.doubleValue));
        }
    } else if (sendCommand) {
        NSInteger mediaCommand = -1;
        if ([command isEqualToString:@"play"]) mediaCommand = 0;
        if ([command isEqualToString:@"toggle"]) mediaCommand = 2;
        if ([command isEqualToString:@"next"]) mediaCommand = 4;
        if ([command isEqualToString:@"previous"]) mediaCommand = 5;
        if (mediaCommand >= 0) {
            NSString *bundleIdentifier = payload[@"bundleIdentifier"];
            if ([bundleIdentifier isKindOfClass:NSString.class]
                && bundleIdentifier.length > 0) {
                if (sendCommandToApp) {
                    Boolean accepted = sendCommandToApp(
                        mediaCommand,
                        NULL,
                        getLocalOrigin ? getLocalOrigin() : NULL,
                        (__bridge CFStringRef)bundleIdentifier,
                        0,
                        mediaQueue,
                        ^(NSInteger result) {
                            WriteJSON(@{
                                @"type": @"commandResult",
                                @"command": command,
                                @"bundleIdentifier": bundleIdentifier,
                                @"result": @(result)
                            });
                            ScheduleRefresh();
                        }
                    );
                    if (!accepted) {
                        WriteError(@"Addressed media command was rejected");
                    }
                    return;
                }
                WriteError(@"Addressed media commands are unavailable");
                return;
            }
            sendCommand(mediaCommand, NULL);
        }
    }
    ScheduleRefresh();
}

static void ReadCommands(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        char *buffer = NULL;
        size_t capacity = 0;
        while (getline(&buffer, &capacity, stdin) >= 0) {
            @autoreleasepool {
                NSString *line = [[NSString alloc] initWithUTF8String:buffer];
                NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *payload = data
                    ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]
                    : nil;
                if ([payload isKindOfClass:NSDictionary.class]) {
                    dispatch_async(mediaQueue, ^{ HandleCommand(payload); });
                }
            }
        }
        free(buffer);
        _exit(0);
    });
}

static void ObserveNotification(const char *symbol) {
    CFStringRef *namePointer = mediaRemoteHandle ? dlsym(mediaRemoteHandle, symbol) : NULL;
    if (!namePointer || !*namePointer) {
        return;
    }
    id token = [[NSNotificationCenter defaultCenter]
        addObserverForName:(__bridge NSString *)*namePointer
        object:nil
        queue:nil
        usingBlock:^(__unused NSNotification *notification) {
            dispatch_async(mediaQueue, ^{ RefreshState(); });
        }];
    if (token) [notificationTokens addObject:token];
}

__attribute__((constructor))
static void StartTopNestMediaHelper(void) {
    @autoreleasepool {
        mediaRemoteHandle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW | RTLD_LOCAL
        );
        if (!mediaRemoteHandle) {
            WriteError(@"MediaRemote could not be loaded");
            return;
        }

        getNowPlayingInfo = dlsym(mediaRemoteHandle, "MRMediaRemoteGetNowPlayingInfo");
        getApplicationIsPlaying = dlsym(
            mediaRemoteHandle,
            "MRMediaRemoteGetNowPlayingApplicationIsPlaying"
        );
        getApplicationPID = dlsym(
            mediaRemoteHandle,
            "MRMediaRemoteGetNowPlayingApplicationPID"
        );
        getLocalOrigin = dlsym(mediaRemoteHandle, "MRMediaRemoteGetLocalOrigin");
        registerForNotifications = dlsym(
            mediaRemoteHandle,
            "MRMediaRemoteRegisterForNowPlayingNotifications"
        );
        sendCommand = dlsym(mediaRemoteHandle, "MRMediaRemoteSendCommand");
        sendCommandToApp = dlsym(mediaRemoteHandle, "MRMediaRemoteSendCommandToApp");
        setElapsedTime = dlsym(mediaRemoteHandle, "MRMediaRemoteSetElapsedTime");

        if (!getNowPlayingInfo) {
            WriteError(@"MediaRemote API changed");
            return;
        }

        mediaQueue = dispatch_queue_create("com.local.topnest.media", DISPATCH_QUEUE_SERIAL);
        notificationTokens = [NSMutableArray array];
        if (registerForNotifications) {
            registerForNotifications(mediaQueue);
        }
        ObserveNotification("kMRMediaRemoteNowPlayingInfoDidChangeNotification");
        ObserveNotification("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
        ObserveNotification("kMRMediaRemoteNowPlayingApplicationDidChangeNotification");
        ReadCommands();
        dispatch_async(mediaQueue, ^{ RefreshState(); });
    }
}
