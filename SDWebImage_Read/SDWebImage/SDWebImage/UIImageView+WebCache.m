/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIImageView+WebCache.h"
#import "objc/runtime.h"
#import "UIView+WebCacheOperation.h"

static char imageURLKey;
static char TAG_ACTIVITY_INDICATOR;
static char TAG_ACTIVITY_STYLE;
static char TAG_ACTIVITY_SHOW;

@implementation UIImageView (WebCache)

- (void)sd_setImageWithURL:(NSURL *)url {
    [self sd_setImageWithURL:url placeholderImage:nil options:0 progress:nil completed:nil];
}

- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:nil];
}

- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:nil];
}

- (void)sd_setImageWithURL:(NSURL *)url completed:(SDWebImageCompletionBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:nil options:0 progress:nil completed:completedBlock];
}

- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletionBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:completedBlock];
}

- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletionBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:completedBlock];
}


/****************
 
具体请求流程
 步骤1:
 UIView相关分类调用各自的接口方法
 UIImageView+WebCache中的方法
 - (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletionBlock)completedBlock;

 
 步骤2:
 步骤1中方法调用了SDWebImageManager的接口方法(传入相关的参数、回调等)获取返回的SDWebImageOperation对象
 调用的SDWebImageManager中的方法
 - (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url
 options:(SDWebImageOptions)options
 progress:(SDWebImageDownloaderProgressBlock)progressBlock
 completed:(SDWebImageCompletionWithFinishedBlock)completedBlock;
 
 步骤3:
 SDWebImageManager的方法中,会创建SDWebImageOperation对象。在设置SDWebImageOperation对象的属性时,会异步查询本地的硬盘中是否有缓存,从而根据情况决定是否进行网络请求。在这个异步查询的回调中,如果需要网络请求,就调用SDWebImageDownloader对象的接口方法进行下载。
 调用的SDWebImageDownloader中的方法
- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageDownloaderCompletedBlock)completedBlock
 
 步骤4:
 SDWebImageDownloader的方法中会保存传入进度回调和完成回调,并且创建下载的operation任务,并将该operation加入到NSOperationQueue中后返回,以上操作都是同步完成的。
 
 创建下载的operation过程涉及到 请求的创建、相关证书的设置等,这些值最终用来初始化了SDWebImageDownloaderOperation对象。
 
 步骤5:
 自定义的SDWebImageDownloaderOperation是抽象NSOperation类的子类。当operation添加到NSOperationQueue中后,系统就会异步调度加入的operation任务。
 operation任务的入口就是operation的start方法。所以在SDWebImageDownloaderOperation对象的start方法中可以看到通过传入的相关参数构建了下载任务,并开启下载。
 
 
 需要注意的问题: 在下载过程中在SDWebImageDownloader中创建了session并且代理设置为了SDWebImageDownloader对象。当网络回调时将这些回调数据转发给了SDWebImageDownloaderOperation对象处理。如果SDWebImageDownloader中的session没有创建,那么SDWebImageDownloaderOperation对象中会自己创建session并自己处理网络回调。但是不论是使用哪个session最终下载任务的启动都是在SDWebImageDownloaderOperation对象的start方法中。
 
****************/







// 加载单张图的最终方法
- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletionBlock)completedBlock {
    
    // 先取消当前imageView的加载
    [self sd_cancelCurrentImageLoad];
    
    // 关联对象，对象保存图片地址
    objc_setAssociatedObject(self, &imageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 不是SDWebImageDelayPlaceholder 就设置placeholder
    if (!(options & SDWebImageDelayPlaceholder)) {
        // 主线程执行异步任务
        dispatch_main_async_safe(^{
            self.image = placeholder;
        });
    }
    
    if (url) {
        // check if activityView is enabled or not 是否展示菊花指示器
        if ([self showActivityIndicatorView]) {
            [self addActivityIndicator];
        }
        // sharedManager是个单例 为了避免内存泄漏使用__weak修饰self
        __weak __typeof(self)wself = self;
        
        // 创建operation
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadImageWithURL:url options:options progress:progressBlock completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
            
            /****  图片下载完成后的回调    ****/
            
            // 移除菊花指示器
            [wself removeActivityIndicator];
            
            // self被释放的场景??
            if (!wself) return;
            
            dispatch_main_sync_safe(^{
                
                if (!wself) return;
                
                //  SDWebImageAvoidAutoSetImage(关闭自动设置image)选项时下载网图片后 让调用者自己处理image
                if (image && (options & SDWebImageAvoidAutoSetImage) && completedBlock)
                {
                    // SDWebImageProgressiveDownloads开启时,会调用多次改回调
                    completedBlock(image, error, cacheType, url);
                    return;
                }
                else if (image) {
                    NSLog(@"自动设置图片");
                    // 自动设置image
                    wself.image = image;
                    [wself setNeedsLayout];
                } else {
                    NSLog(@"下载图片失败后设置占位图");
                    // 下载图片失败后设置占位图
                    if ((options & SDWebImageDelayPlaceholder)) {
                        wself.image = placeholder;
                        [wself setNeedsLayout];
                    }
                }
                if (completedBlock && finished) {
                    // finished图片完全下载完,进行回调
                    completedBlock(image, error, cacheType, url);
                }
            });
        }];
        
        // 将该operation添加到operationDictionary:每个调用sd_setImageLoadOperation方法的对象被都添加了一个operationDictionary
        [self sd_setImageLoadOperation:operation forKey:@"UIImageViewImageLoad"];
        
        
    } else {
        // 主线程异步
        dispatch_main_async_safe(^{
            [self removeActivityIndicator];
            // 设置错误信息
            if (completedBlock) {
                NSError *error = [NSError errorWithDomain:SDWebImageErrorDomain code:-1 userInfo:@{NSLocalizedDescriptionKey : @"Trying to load a nil url"}];
                completedBlock(nil, error, SDImageCacheTypeNone, url);
            }
        });
    }
}

- (void)sd_setImageWithPreviousCachedImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletionBlock)completedBlock {
    
    // 通过url查找缓存的图片
    NSString *key = [[SDWebImageManager sharedManager] cacheKeyForURL:url];
    UIImage *lastPreviousCachedImage = [[SDImageCache sharedImageCache] imageFromDiskCacheForKey:key];
    // 通过缓存的图设置占位图
    [self sd_setImageWithURL:url placeholderImage:lastPreviousCachedImage ?: placeholder options:options progress:progressBlock completed:completedBlock];    
}

- (NSURL *)sd_imageURL {
    return objc_getAssociatedObject(self, &imageURLKey);
}
// 加载一组Url
- (void)sd_setAnimationImagesWithURLs:(NSArray *)arrayOfURLs {
    // 取消一组operations
    [self sd_cancelCurrentAnimationImagesLoad];
    
    __weak __typeof(self)wself = self;

    NSMutableArray *operationsArray = [[NSMutableArray alloc] init];

    for (NSURL *logoImageURL in arrayOfURLs) {
        
        id <SDWebImageOperation> operation = [SDWebImageManager.sharedManager downloadImageWithURL:logoImageURL options:0 progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished, NSURL *imageURL) {
            
            if (!wself) return;
            dispatch_main_sync_safe(^{
                // 强引用wself 防止在操作时被释放
                __strong UIImageView *sself = wself;
                
                [sself stopAnimating];
                
                if (sself && image) {
                    NSMutableArray *currentImages = [[sself animationImages] mutableCopy];
                    if (!currentImages) {
                        currentImages = [[NSMutableArray alloc] init];
                    }
                    [currentImages addObject:image];

                    sself.animationImages = currentImages;
                    [sself setNeedsLayout];
                }
                [sself startAnimating];
            });
        }];
        // 将operation添加到数组中保存
        [operationsArray addObject:operation];
    }

    // 将保存operation的数组添加到operationDictionary
    [self sd_setImageLoadOperation:[NSArray arrayWithArray:operationsArray] forKey:@"UIImageViewAnimationImages"];
}


// sd_cancelImageLoadOperationWithKey是分类UIView+WebCacheOperation的方法
// 取消单张图片的加载
- (void)sd_cancelCurrentImageLoad {
    [self sd_cancelImageLoadOperationWithKey:@"UIImageViewImageLoad"];
}
// 取消一组图片的加载
- (void)sd_cancelCurrentAnimationImagesLoad {
    [self sd_cancelImageLoadOperationWithKey:@"UIImageViewAnimationImages"];
}


#pragma mark -
- (UIActivityIndicatorView *)activityIndicator {
    return (UIActivityIndicatorView *)objc_getAssociatedObject(self, &TAG_ACTIVITY_INDICATOR);
}

- (void)setActivityIndicator:(UIActivityIndicatorView *)activityIndicator {
    objc_setAssociatedObject(self, &TAG_ACTIVITY_INDICATOR, activityIndicator, OBJC_ASSOCIATION_RETAIN);
}

- (void)setShowActivityIndicatorView:(BOOL)show{
    objc_setAssociatedObject(self, &TAG_ACTIVITY_SHOW, [NSNumber numberWithBool:show], OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)showActivityIndicatorView{
    return [objc_getAssociatedObject(self, &TAG_ACTIVITY_SHOW) boolValue];
}

- (void)setIndicatorStyle:(UIActivityIndicatorViewStyle)style{
    objc_setAssociatedObject(self, &TAG_ACTIVITY_STYLE, [NSNumber numberWithInt:style], OBJC_ASSOCIATION_RETAIN);
}

- (int)getIndicatorStyle{
    return [objc_getAssociatedObject(self, &TAG_ACTIVITY_STYLE) intValue];
}

- (void)addActivityIndicator {
    if (!self.activityIndicator) {
        self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:[self getIndicatorStyle]];
        self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        
        // 添加UIActivityIndicatorView
        dispatch_main_async_safe(^{
            
            [self addSubview:self.activityIndicator];

            [self addConstraint:[NSLayoutConstraint constraintWithItem:self.activityIndicator
                                                             attribute:NSLayoutAttributeCenterX
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:self
                                                             attribute:NSLayoutAttributeCenterX
                                                            multiplier:1.0
                                                              constant:0.0]];
            [self addConstraint:[NSLayoutConstraint constraintWithItem:self.activityIndicator
                                                             attribute:NSLayoutAttributeCenterY
                                                             relatedBy:NSLayoutRelationEqual
                                                                toItem:self
                                                             attribute:NSLayoutAttributeCenterY
                                                            multiplier:1.0
                                                              constant:0.0]];
        });
    }

    dispatch_main_async_safe(^{
        [self.activityIndicator startAnimating];
    });

}

- (void)removeActivityIndicator {
    if (self.activityIndicator) {
        [self.activityIndicator removeFromSuperview];
        self.activityIndicator = nil;
    }
}

@end











/***********    废弃        *********/
@implementation UIImageView (WebCacheDeprecated)

- (NSURL *)imageURL {
    return [self sd_imageURL];
}

- (void)setImageWithURL:(NSURL *)url {
    [self sd_setImageWithURL:url placeholderImage:nil options:0 progress:nil completed:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:nil];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:nil];
}

- (void)setImageWithURL:(NSURL *)url completed:(SDWebImageCompletedBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:nil options:0 progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        if (completedBlock) {
            completedBlock(image, error, cacheType);
        }
    }];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder completed:(SDWebImageCompletedBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:0 progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        if (completedBlock) {
            completedBlock(image, error, cacheType);
        }
    }];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options completed:(SDWebImageCompletedBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:options progress:nil completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        if (completedBlock) {
            completedBlock(image, error, cacheType);
        }
    }];
}

- (void)setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletedBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:placeholder options:options progress:progressBlock completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        if (completedBlock) {
            completedBlock(image, error, cacheType);
        }
    }];
}

- (void)sd_setImageWithPreviousCachedImageWithURL:(NSURL *)url andPlaceholderImage:(UIImage *)placeholder options:(SDWebImageOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageCompletionBlock)completedBlock {
    [self sd_setImageWithPreviousCachedImageWithURL:url placeholderImage:placeholder options:options progress:progressBlock completed:completedBlock];
}

- (void)cancelCurrentArrayLoad {
    [self sd_cancelCurrentAnimationImagesLoad];
}

- (void)cancelCurrentImageLoad {
    [self sd_cancelCurrentImageLoad];
}

- (void)setAnimationImagesWithURLs:(NSArray *)arrayOfURLs {
    [self sd_setAnimationImagesWithURLs:arrayOfURLs];
}

@end
