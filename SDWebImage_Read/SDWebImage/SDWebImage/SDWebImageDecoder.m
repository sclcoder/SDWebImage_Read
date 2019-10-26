/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * Created by james <https://github.com/mystcolor> on 9/28/11.
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDecoder.h"
@implementation UIImage (ForceDecode)

// 这里的解压缩指的是，将压缩过的图片（JPEG、PNG、WebP、APNG）解压成未压缩的位图。

/** http://blog.leichunfeng.com/blog/2017/02/20/talking-about-the-decompression-of-the-image-in-ios/
 加载图片流程
 
    1.假设用 +[UIImage imageWithContentsOfFile:] 加载图片，它会创建 UIImage 的一个引用，此时并不会发生解码
    2.返回的 UIImage 赋值给 UIImageView
    3.隐式 CATransaction 捕获到图层树（layer tree）的修改 在主线程 run loop 的下一个循环时，Core Animation 会提交这些隐式 CATransaction，图片可能会创建一个 copy。在 copy 过程中，可能会发生如下一些或者全部步骤：
 
         a.分配管理文件 IO、解压缩操作的内存缓冲区
         b.文件数据从磁盘读取到内存中
         c.压缩的图片数据解码成未压缩的位图格式，这通常是非常耗时的 CPU 操作
         d.Core Animation 将解压缩后的位图数据渲染到图层（layer）上
         其中「流程d步骤c」中图片的解压缩是一个非常耗时的操作，而且默认发生在主线程中。当显示的图片过多时，容易导致性能问题。特别是滚动时，尤为突出。

 因此我们可以将图片的解压缩放在后台线程，不堵塞主线程。这就需要提前在后台线程解压缩，之后将解压缩后的图片在主线程赋值给 UIImageView。
 */
+ (UIImage *)decodedImageWithImage:(UIImage *)image {
    // while downloading huge amount of images
    // autorelease the bitmap context
    // and all vars to help system to free memory
    // when there are memory warning.
    // on iOS7, do not forget to call
    // [[SDImageCache sharedImageCache] clearMemory];
    
    if (image == nil) { // Prevent "CGBitmapContextCreateImage: invalid context 0x0" error
        return nil;
    }
    
    @autoreleasepool{
        // do not decode animated images
        if (image.images != nil) {
            return image;
        }
        
        CGImageRef imageRef = image.CGImage;
        
        CGImageAlphaInfo alpha = CGImageGetAlphaInfo(imageRef);
        BOOL anyAlpha = (alpha == kCGImageAlphaFirst ||
                         alpha == kCGImageAlphaLast ||
                         alpha == kCGImageAlphaPremultipliedFirst ||
                         alpha == kCGImageAlphaPremultipliedLast);
        if (anyAlpha) { // 有alpha通道image直接返回 即SD不支持对含有alpha通道（png）图像的解码
            return image;
        }
        
        // current
        CGColorSpaceModel imageColorSpaceModel = CGColorSpaceGetModel(CGImageGetColorSpace(imageRef));
        CGColorSpaceRef colorspaceRef = CGImageGetColorSpace(imageRef);
        
        BOOL unsupportedColorSpace = (imageColorSpaceModel == kCGColorSpaceModelUnknown ||
                                      imageColorSpaceModel == kCGColorSpaceModelMonochrome ||
                                      imageColorSpaceModel == kCGColorSpaceModelCMYK ||
                                      imageColorSpaceModel == kCGColorSpaceModelIndexed);
        if (unsupportedColorSpace) {
            colorspaceRef = CGColorSpaceCreateDeviceRGB();
        }
        
        size_t width = CGImageGetWidth(imageRef);
        size_t height = CGImageGetHeight(imageRef);
        NSUInteger bytesPerPixel = 4;
        NSUInteger bytesPerRow = bytesPerPixel * width;
        NSUInteger bitsPerComponent = 8;


        // kCGImageAlphaNone is not supported in CGBitmapContextCreate.
        // Since the original image here has no alpha info, use kCGImageAlphaNoneSkipLast
        // to create bitmap graphics contexts without alpha info.
        CGContextRef context = CGBitmapContextCreate(NULL,
                                                     width,
                                                     height,
                                                     bitsPerComponent,
                                                     bytesPerRow,
                                                     colorspaceRef,
                                                     kCGBitmapByteOrderDefault|kCGImageAlphaNoneSkipLast);
        
        // Draw the image into the context and retrieve the new bitmap image without alpha
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef);
        CGImageRef imageRefWithoutAlpha = CGBitmapContextCreateImage(context);
        UIImage *imageWithoutAlpha = [UIImage imageWithCGImage:imageRefWithoutAlpha
                                                         scale:image.scale
                                                   orientation:image.imageOrientation];
        
        if (unsupportedColorSpace) {
            CGColorSpaceRelease(colorspaceRef);
        }
        
        CGContextRelease(context);
        CGImageRelease(imageRefWithoutAlpha);
        return imageWithoutAlpha;
    }
}

@end
