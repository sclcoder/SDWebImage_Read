//
// Created by Fabrice Aneche on 06/01/14.
// Copyright (c) 2014 Dailymotion. All rights reserved.
//

#import "NSData+ImageContentType.h"


@implementation NSData (ImageContentType)

+ (NSString *)sd_contentTypeForImageData:(NSData *)data {
    uint8_t c;
    /**
     Copies a number of bytes from the start of the receiver's data into a given buffer.
     The number of bytes copied is the smaller of the length parameter and the length of the data encapsulated in the object.
     Parameters
     buffer
     A buffer into which to copy data.
     length
     The number of bytes from the start of the receiver's data to copy to buffer.
     */
    // 获取第一个字节
    [data getBytes:&c length:1];
    
    // 图片的头文件信息 https://www.cnblogs.com/Wendy_Yu/archive/2011/12/27/2303118.html
    switch (c) {
            // 判断图片类型
        case 0xFF:
            return @"image/jpeg";
        case 0x89:
            return @"image/png";
        case 0x47:
            return @"image/gif";
        case 0x49:
        case 0x4D:
            return @"image/tiff";
        case 0x52:
            // R as RIFF for WEBP
            if ([data length] < 12) {
                return nil;
            }

            NSString *testString = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, 12)] encoding:NSASCIIStringEncoding];
            if ([testString hasPrefix:@"RIFF"] && [testString hasSuffix:@"WEBP"]) {
                return @"image/webp";
            }

            return nil;
    }
    return nil;
}

@end


@implementation NSData (ImageContentTypeDeprecated)

+ (NSString *)contentTypeForImageData:(NSData *)data {
    return [self sd_contentTypeForImageData:data];
}

@end
