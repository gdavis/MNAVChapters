//
//  MNAVChapters.h
//  MNAVChapters
//
//  Created by Michael Nisi on 02.08.13.
//  Copyright (c) 2013 Michael Nisi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CMTime.h>
#import <AVFoundation/AVFoundation.h>

#if TARGET_OS_MAC
#import <AppKit/AppKit.h>

#else
#import <UIKit/UIKit.h>
#endif

@interface MNAVChapter : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *url;
@property (nonatomic) CMTime time;
@property (nonatomic) CMTime duration;
#if TARGET_OS_MAC
@property (nonatomic) NSImage *artwork;
#else
@property (nonatomic) UIImage *artwork;
#endif

- (BOOL)isEqualToChapter:(MNAVChapter *)aChapter;
- (MNAVChapter *)initWithTime:(CMTime)time duration:(CMTime)duration;
+ (MNAVChapter *)chapterWithTime:(CMTime)time duration:(CMTime)duration;
@end

@interface MNAVChapterReader : NSObject
+ (NSArray *)chaptersFromAsset:(AVAsset *)asset;
@end

# pragma mark - Internal

@protocol MNAVChapterReader <NSObject>
- (NSArray *)chaptersFromAsset:(AVAsset *)asset;
@end

@interface MNAVChapterReaderMP3 : NSObject <MNAVChapterReader>
- (MNAVChapter *)chapterFromFrame:(NSData *)data;
@end

@interface MNAVChapterReaderMP4 : NSObject <MNAVChapterReader>
@end
