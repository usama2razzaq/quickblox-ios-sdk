//
//  Log.m
//  sample-conference-videochat
//
//  Created by Injoit on 2/25/19.
//  Copyright © 2019 Quickblox. All rights reserved.
//

#import "Log.h"

static BOOL logEnabled = YES;

void LogSetEnabled(BOOL enabled) {
    logEnabled = enabled;
}

BOOL LogEnabled() {
    return logEnabled;
}

void Log(NSString *format, ...) {
    if (logEnabled)
    {
        va_list L;
        va_start(L, format);
        @autoreleasepool {
            NSLogv(format, L);
        }
        va_end(L);
    }
}
