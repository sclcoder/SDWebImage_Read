//
//  SDWebImageCompat.m
//  SDWebImage
//
//  Created by Olivier Poitrey on 11/12/12.
//  Copyright (c) 2012 Dailymotion. All rights reserved.
//

#import "SDWebImageCompat.h"

#if !__has_feature(objc_arc)
#error SDWebImage is ARC only. Either turn on ARC for the project or use -fobjc-arc flag
#endif

// 获取相应scale的image
inline UIImage *SDScaledImageForKey(NSString *key, UIImage *image) {
    if (!image) {
        return nil;
    }
    // default is nil for non-animated images
    if ([image.images count] > 0) {
        NSMutableArray *scaledImages = [NSMutableArray array];

        for (UIImage *tempImage in image.images) {
            [scaledImages addObject:SDScaledImageForKey(key, tempImage)];
        }

        return [UIImage animatedImageWithImages:scaledImages duration:image.duration];
    }
    else {
        if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
            CGFloat scale = 1;
            if (key.length >= 8) {
                NSRange range = [key rangeOfString:@"@2x."];
                if (range.location != NSNotFound) {
                    scale = 2.0;
                }
                
                range = [key rangeOfString:@"@3x."];
                if (range.location != NSNotFound) {
                    scale = 3.0;
                }
            }
            
            /**
             (lldb) po key
             http://pic40.nipic.com/20140412/18428321_144447597175_2.jpg
             
             (lldb) po range
             location=9223372036854775807, length=0
             
             (lldb) po NSNotFound
             9223372036854775807

             */
            
            UIImage *scaledImage = [[UIImage alloc] initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
            image = scaledImage;
            
            /**
             Summary
             
             Initializes and returns an image object with the specified scale and orientation factors
             Declaration
             
             - (instancetype)initWithCGImage:(CGImageRef)cgImage scale:(CGFloat)scale orientation:(UIImageOrientation)orientation;
             Parameters
             
             imageRef
             The Quartz image object.
             scale
             The scale factor to assume when interpreting the image data. Applying a scale factor of 1.0 results in an image whose size matches the pixel-based dimensions of the image. Applying a different scale factor changes the size of the image as reported by the size property.
             orientation
             The orientation of the image data. You can use this parameter to specify any rotation factors applied to the image.
             Returns
             
             An initialized UIImage object. In Objective-C, this method returns nil if the ciImage parameter is nil.

             **/
        }
        return image;
    }
}

NSString *const SDWebImageErrorDomain = @"SDWebImageErrorDomain";
