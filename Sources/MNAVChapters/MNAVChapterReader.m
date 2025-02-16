//
//  MNAVChapters.m
//  MNAVChapters
//
//  Created by Michael Nisi on 02.08.13.
//  Copyright (c) 2013 Michael Nisi. All rights reserved.
//

#import "include/MNAVChapterReader.h"

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#define _unused(x) ((void)(x))

# pragma mark - MNAVChapterReader

static NSString *const MNAVMetadataFormatApple = @"com.apple.itunes";
static NSString *const MNAVMetadataFormatMP4 = @"org.mp4ra";
static NSString *const MNAVMetadataFormatID3 = @"org.id3";

@implementation MNAVChapterReader

+ (NSArray *)chaptersFromAsset:(AVAsset *)asset {
    NSArray *formats = asset.availableMetadataFormats;
    id <MNAVChapterReader> parser = nil;
    NSArray *result = nil;
    for (NSString *format in formats) {
        if ([format isEqualToString:MNAVMetadataFormatMP4]) {
            parser = [MNAVChapterReaderMP4 new];
        } else if ([format isEqualToString:MNAVMetadataFormatID3]) {
            parser = [MNAVChapterReaderMP3 new];
        }
        result = [parser chaptersFromAsset:asset];
    }
    return result;
}

@end

# pragma mark - MNAVChapter

@implementation MNAVChapter

- (BOOL)isEqual:(id)object {
    return [self isEqualToChapter:object];
}

- (BOOL)isEqualToChapter:(MNAVChapter *)aChapter {
    return [self.title isEqualToString:aChapter.title]
    && (self.url == aChapter.url || [self.url isEqualToString:aChapter.url])
    && CMTIME_COMPARE_INLINE(self.time, ==, aChapter.time);
    // && CMTIME_COMPARE_INLINE(self.duration, ==, aChapter.duration);
}

- (MNAVChapter *)initWithTime:(CMTime)time duration:(CMTime)duration {
    self = [super init];
    if (self) {
        _time = time;
        _duration = duration;
        _hidden = NO;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"chapter: [%@] %@, %@, %lld, %lld %@",
            self.identifier, self.title, self.url, self.time.value, self.duration.value, self.hidden ? @"Hidden":@""];
}

+ (MNAVChapter *)chapterWithTime:(CMTime)time duration:(CMTime)duration {
    return [[self alloc] initWithTime:time duration:duration];
}

@end

# pragma mark - MNAVChapterReaderMP4

@implementation MNAVChapterReaderMP4
- (NSArray *)chaptersFromAsset:(AVAsset *)asset {
    NSArray *languages = [self languagesForAsset:asset];
    NSArray *groups = [asset chapterMetadataGroupsBestMatchingPreferredLanguages:languages];
    NSUInteger chapterCount = groups.count;
    NSMutableArray *chapters = [[NSMutableArray alloc] initWithCapacity:chapterCount];
    for (AVTimedMetadataGroup *group in groups) {
        MNAVChapter *chapter = [MNAVChapter new];
        chapter.title = [self titleFromGroup:group];
        chapter.artwork = [self imageFromGroup:group];
        chapter.url = [self urlFromGroup:group forTitle:chapter.title];
        chapter.time = [self timeFromGroup:group];
        chapter.duration = [self durationFromGroup:group];
        [chapters addObject:chapter];
    }
    return chapters;
}

- (NSArray *)languagesForAsset:(AVAsset *)asset {
    NSArray *preferred = [NSLocale preferredLanguages];
    NSMutableArray *languages = [NSMutableArray arrayWithArray:preferred];
    NSArray *locales = [asset availableChapterLocales];
    for (NSLocale *locale in locales) {
        [languages addObject:[locale localeIdentifier]];
    }
    return languages;
}

- (CMTime)timeFromGroup:(AVTimedMetadataGroup *)group {
    NSArray *items = [self itemsFromArray:group.items withKey:@"title"];
    AVMetadataItem *item = items[0];
    return item.time;
}

- (CMTime)durationFromGroup:(AVTimedMetadataGroup *)group {
    NSArray *items = [self itemsFromArray:group.items withKey:@"title"];
    AVMetadataItem *item = items[0];
    return item.duration;
}

- (NSString *)urlFromGroup:(AVTimedMetadataGroup *)group forTitle:(NSString *)title {
    NSArray *items = [self itemsFromArray:group.items withKey:@"title"];
    NSString *href = nil;
    for (AVMetadataItem *item in items) {
        if ([item.stringValue isEqualToString:title] && item.extraAttributes) {
            href = item.extraAttributes[@"HREF"];
            if (href) break;
        }
    }
    return href;
}

- (NSString *)titleFromGroup:(AVTimedMetadataGroup *)group {
    AVMetadataItem *item = [self itemsFromArray:group.items withKey:@"title"][0];
    return item.stringValue;
}

#if TARGET_OS_OSX
- (NSImage *)imageFromGroup:(AVTimedMetadataGroup *)group {
    NSArray *itemArray = [self itemsFromArray:group.items withKey:@"artwork"];
    if ([itemArray count] > 0) {
        AVMetadataItem *item = itemArray[0];
        return [[NSImage new] initWithData:item.dataValue];
    }
    return NULL;
}

#else
- (UIImage *)imageFromGroup:(AVTimedMetadataGroup *)group {
    NSArray *itemArray = [self itemsFromArray:group.items withKey:@"artwork"];
    if ([itemArray count] > 0) {
        AVMetadataItem *item = itemArray[0];

        return [UIImage imageWithData:item.dataValue];
    }
    return NULL;
}
#endif

- (NSArray *)itemsFromArray:(NSArray *)items withKey:(NSString *)key {
    return [AVMetadataItem metadataItemsFromArray:items withKey:key keySpace:nil];
}
@end

# pragma mark - MNAVChapterReaderMP3

#define SUBDATA(data,loc,len) [data subdataWithRange:NSMakeRange(loc, len)]

typedef NS_ENUM(NSUInteger, ID3Frame) {
    ID3FrameEncoding = 1,
    ID3FrameShortDescription = 1,
    ID3FramePictureType = 1,
    ID3FrameFlags = 2,
    ID3FrameLanguage = 3,
    ID3FrameSize = 4,
    ID3FrameID = 4,
    ID3FrameFrame = 10
};

typedef NS_ENUM(NSUInteger, ID3FramePositions) {
    ID3FramePositionID = 0,
    ID3FramePositionSize = ID3FramePositionID + ID3FrameID,
    ID3FramePositionFlags = ID3FramePositionSize + ID3FrameSize,
    ID3FramePositionEncoding = ID3FramePositionFlags + ID3FrameFlags,
    ID3FramePositionText = ID3FramePositionEncoding + ID3FrameEncoding
};

typedef NS_ENUM(NSUInteger, ID3Header) {
    ID3HeaderSize = 4
};

// http://id3.org/id3v2.4.0-structure
typedef NS_ENUM(NSUInteger, ID3TextEncoding) {
    ID3TextEncodingISO = 0,
    ID3TextEncodingUTF16 = 1,
    ID3TextEncodingUTF16BE = 2,
    ID3TextEncodingUTF8 = 3
};

static NSString *const MNAVMetadataID3MetadataKeyChapter = @"CHAP";
static NSString *const MNAVMetadataID3MetadataKeyTableOfContents = @"CTOC";

unsigned long is_set(char *bytes, long size);
long btoi(char* bytes, long size, long offset);

@implementation MNAVChapterReaderMP3

- (NSArray *)chaptersFromAsset:(AVAsset *)asset {
    NSArray *its = [asset metadataForFormat:MNAVMetadataFormatID3];
    NSArray *items = [AVMetadataItem metadataItemsFromArray:its
                                                    withKey:MNAVMetadataID3MetadataKeyChapter
                                                   keySpace:MNAVMetadataFormatID3];
    
    NSArray <NSString *>*chapterIdentifiers = [self tableOfContentsFromMetadata:its];
    
    NSMutableArray *chapters = [NSMutableArray new];
    for (AVMetadataItem *item in items) {
        MNAVChapter *chapter = [self chapterFromFrame:item.dataValue];
        chapter.hidden = ![chapterIdentifiers containsObject:chapter.identifier];
        
        [chapters addObject:chapter];
    }
    
    return [chapters sortedArrayUsingComparator:
            ^NSComparisonResult(MNAVChapter *a, MNAVChapter *b) {
                return CMTimeCompare(a.time, b.time);
            }];
}

- (NSArray <NSString *>*)tableOfContentsFromMetadata:(NSArray *)metadata {
    NSArray *tablesOfContents = [AVMetadataItem metadataItemsFromArray:metadata
                                                               withKey:MNAVMetadataID3MetadataKeyTableOfContents
                                                              keySpace:MNAVMetadataFormatID3];
    
    AVMetadataItem *toc = tablesOfContents.firstObject;
    
    if (!toc) {
        return @[];
    }
    
    NSData *tocData = toc.dataValue;
    
    NSUInteger flagsSize = 1;
    NSUInteger chapterCountSize = 1;
    NSUInteger index = [self dataToTermInData:tocData].length + flagsSize;
    
    NSData *numberOfChaptersData = SUBDATA(tocData, index, chapterCountSize);
    NSInteger numberOfChapters = btoi((char *)numberOfChaptersData.bytes, chapterCountSize, 0);
    
    
    
    NSData *chapterData = SUBDATA(tocData, index+chapterCountSize, tocData.length-chapterCountSize-index);
    NSMutableArray *chapterIdentifiers = [NSMutableArray new];
    
    NSArray *splitData = [self splitDataByTerminator:chapterData];
    
    if (numberOfChapters == 0) {
        numberOfChapters = splitData.count;
    }
    
    for(NSData *subData in [splitData subarrayWithRange:NSMakeRange(0, numberOfChapters)]) {
        @try {
            NSString *chaperIdentifier = [NSString stringWithUTF8String:subData.bytes];
            [chapterIdentifiers addObject:chaperIdentifier];
        }
        @catch (NSException *exception) {
            //
        }
    }
    
    return [chapterIdentifiers copy];
}

- (MNAVChapter *)chapterFromFrame:(NSData *)data {
    NSData *identifierData = [self dataToTermInData:data];
    NSString *identifier = [NSString stringWithUTF8String:identifierData.bytes];
    
    NSUInteger index = identifierData.length;
    
    NSData *startTimeData = SUBDATA(data, index, ID3HeaderSize);
    NSData *endTimeData = SUBDATA(data, index += ID3HeaderSize, ID3HeaderSize);
    NSData *startOffsetData = SUBDATA(data, index += ID3HeaderSize, ID3HeaderSize);
    NSData *endOffsetData = SUBDATA(data, index += ID3HeaderSize, ID3HeaderSize);
    
    NSInteger startTime = btoi((char *)startTimeData.bytes, startTimeData.length, 0);
    NSInteger endTime = btoi((char *)endTimeData.bytes, endTimeData.length, 0);
    
    BOOL hasStartOffset = is_set((char *)startOffsetData.bytes, startOffsetData.length);
    assert(!hasStartOffset);
    _unused(hasStartOffset); // fix for unused warning
    // NSUInteger startOffset = btoi((char *)startOffsetData.bytes, startOffsetData.length, 0);
    
    BOOL hasEndOffset = is_set((char *)endOffsetData.bytes, endOffsetData.length);
    assert(!hasEndOffset);
    _unused(hasEndOffset); // fix for unused warning
    // NSUInteger endOffset = btoi((char *)endOffsetData.bytes, endOffsetData.length, 0);
    
    MNAVChapter *chapter = [MNAVChapter new];
    
    chapter.identifier = identifier;
    chapter.time = CMTimeMake(startTime, 1000);
    chapter.duration = CMTimeMake(endTime - startTime, 1000);
    chapter.title = [self titleInData:data];
    chapter.url = [self userURLInData:data];
    chapter.artwork = [self imageInData:data];
    
    return chapter;
}

#if TARGET_OS_OSX
- (NSImage *)imageInData:(NSData *)data {
    NSImage *result = nil;

    @try {
        NSRange range = [self rangeOfFrameWithID:AVMetadataID3MetadataKeyAttachedPicture inData:data];
        unsigned long loc = range.location;

        if (loc==NSNotFound) {
            return nil;
        }

        NSData *sizeData = SUBDATA(data, loc + ID3FramePositionSize, ID3FrameSize);
        NSInteger size =  btoi((char *)sizeData.bytes, sizeData.length, 0);

        //        NSData *textEncodingData = SUBDATA(data, loc + ID3FramePositionEncoding, ID3FrameEncoding);
        //        NSInteger textEncodingValue = btoi((char *)textEncodingData.bytes, textEncodingData.length, 0);
        //        NSInteger textEncoding = [self textEncoding:textEncodingValue];

        NSData *content = SUBDATA(data, loc + ID3FrameFrame + ID3FrameEncoding, size - ID3FrameEncoding);

        NSData *mimeTypeData = [self dataToTermInData:content];
        //        NSString *mimeType = [NSString stringWithUTF8String:mimeTypeData.bytes];

        content = SUBDATA(content, mimeTypeData.length+ID3FrameEncoding, content.length-mimeTypeData.length-ID3FrameEncoding);

        NSData *imageDescriptionData = [self dataToTermInData:content];
        //        NSString *imageDescriptionText = [NSString stringWithUTF8String:imageDescriptionData.bytes];

        content = SUBDATA(content, imageDescriptionData.length, content.length-imageDescriptionData.length);

        result = [[NSImage new] initWithData:content];
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        return result;
    }
}
#else
- (UIImage *)imageInData:(NSData *)data {
    UIImage *result = nil;
    
    @try {
        NSRange range = [self rangeOfFrameWithID:AVMetadataID3MetadataKeyAttachedPicture inData:data];
        unsigned long loc = range.location;
        
        if (loc==NSNotFound) {
            return nil;
        }
        
        NSData *sizeData = SUBDATA(data, loc + ID3FramePositionSize, ID3FrameSize);
        NSInteger size =  btoi((char *)sizeData.bytes, sizeData.length, 0);
        
        //        NSData *textEncodingData = SUBDATA(data, loc + ID3FramePositionEncoding, ID3FrameEncoding);
        //        NSInteger textEncodingValue = btoi((char *)textEncodingData.bytes, textEncodingData.length, 0);
        //        NSInteger textEncoding = [self textEncoding:textEncodingValue];
        
        NSData *content = SUBDATA(data, loc + ID3FrameFrame + ID3FrameEncoding, size - ID3FrameEncoding);
        
        NSData *mimeTypeData = [self dataToTermInData:content];
        //        NSString *mimeType = [NSString stringWithUTF8String:mimeTypeData.bytes];
        
        content = SUBDATA(content, mimeTypeData.length+ID3FrameEncoding, content.length-mimeTypeData.length-ID3FrameEncoding);
        
        NSData *imageDescriptionData = [self dataToTermInData:content];
        //        NSString *imageDescriptionText = [NSString stringWithUTF8String:imageDescriptionData.bytes];
        
        content = SUBDATA(content, imageDescriptionData.length, content.length-imageDescriptionData.length);
        
        result = [UIImage imageWithData:content];
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        return result;
    }
}
#endif

- (NSString *)userURLInData:(NSData *)data {
    NSString *result = nil;
    
    @try {
        NSRange range = [self rangeOfFrameWithID:AVMetadataID3MetadataKeyUserURL inData:data];
        if (range.location == NSNotFound) {
            return result;
        }
        
        unsigned long loc = range.location;
        
        NSData *sizeData = SUBDATA(data, loc + ID3FramePositionSize, ID3FrameSize);
        NSInteger size =  btoi((char *)sizeData.bytes, sizeData.length, 0);
        
        NSData *encData = SUBDATA(data, loc + ID3FramePositionEncoding, ID3FrameEncoding);
        NSInteger encValue = btoi((char *)encData.bytes, encData.length, 0);
        NSInteger encoding = [self textEncoding:encValue];
        
        NSData *content = SUBDATA(data, loc + ID3FrameFrame + ID3FrameEncoding, size - ID3FrameEncoding);
        NSUInteger index = [self dataToTermInData:content].length;
        NSData *url = SUBDATA(content, index, size - index - ID3FrameEncoding);
        NSString *str = [[NSString alloc] initWithBytes:url.bytes length:url.length encoding:encoding];
        
        result = [str stringByRemovingPercentEncoding];
    } @catch (NSException * e) {
        //
    } @finally {
        return result;
    }
}

- (NSString *)titleInData:(NSData *)data {
    NSString *result = nil;
    @try {
        NSRange range = [self rangeOfFrameWithID:AVMetadataID3MetadataKeyTitleDescription inData:data];
        unsigned long loc = range.location;
        
        NSData *sizeData = SUBDATA(data, loc + ID3FramePositionSize, ID3FrameSize);
        NSUInteger size =  btoi((char *)sizeData.bytes, sizeData.length, 0);
        
        NSData *encData = SUBDATA(data, loc + ID3FramePositionEncoding, ID3FrameEncoding);
        NSInteger encValue = btoi((char *)encData.bytes, encData.length, 0);
        NSInteger encoding = [self textEncoding:encValue];
        
        NSData *titleData = SUBDATA(data, loc + ID3FramePositionText, size - ID3FrameEncoding);
        
        result = [[NSString alloc] initWithBytes:titleData.bytes
                                          length:titleData.length
                                        encoding:encoding];
    }
    @catch (NSException *exception) {
        //
    }
    @finally {
        return result;
    }
}

- (NSRange)rangeOfFrameWithID:(NSString *)frameID inData:(NSData *)data {
    NSData *d = [NSData dataWithBytes:[frameID UTF8String] length:ID3FrameID];
    return [data rangeOfData:d options:NSDataSearchBackwards range:NSMakeRange(0, data.length)];
}

- (NSData *)dataToTermInData:(NSData *)data {
    NSUInteger maxLength = 1;
    uint8_t buffer[maxLength];
    BOOL terminated = NO;
    NSInputStream *stream = [NSInputStream inputStreamWithData:data];
    NSMutableData *result = [NSMutableData new];
    [stream open];
    while([stream read:buffer maxLength:maxLength] > 0 && !terminated) {
        [result appendBytes:buffer length:1];
        terminated = *(char *)buffer == '\0';
    }
    [stream close];
    
    return result;
}

- (NSArray *)splitDataByTerminator:(NSData *)data {
    NSUInteger maxLength = 1;
    uint8_t buffer[maxLength];
    BOOL terminated = NO;
    NSInputStream *stream = [NSInputStream inputStreamWithData:data];
    
    NSMutableArray *splitData = [NSMutableArray new];
    
    [stream open];
    NSMutableData *result = [NSMutableData new];
    while([stream read:buffer maxLength:maxLength] > 0) {
        [result appendBytes:buffer length:1];
        terminated = *(char *)buffer == '\0';
        
        if (terminated) {
            [splitData addObject:result];
            result = [NSMutableData new];
        }
    }
    
    [stream close];
    
    return [splitData copy];
}

- (NSInteger)textEncoding:(NSInteger)i {
    switch (i) {
        case ID3TextEncodingISO:
            return NSASCIIStringEncoding;
        case ID3TextEncodingUTF8:
            return NSUTF8StringEncoding;
        case ID3TextEncodingUTF16:
            return NSUTF16StringEncoding;
        case ID3TextEncodingUTF16BE:
            return NSUTF16BigEndianStringEncoding;
        default:
            return NSASCIIStringEncoding;
    }
}

@end

#pragma mark - utils

unsigned long is_set(char *bytes, long size) {
    unsigned int result = 0x00;
    while (size-- && !result) {
        result = bytes[size] != '\xff';
    }
    return result;
}

long btoi(char* bytes, long size, long offset) {
    int i;
    unsigned int result = 0x00;
    for(i = 0; i < size; i++) {
        result = result << 8;
        result = result | (unsigned char) bytes[offset + i];
    }
    return result;
}
