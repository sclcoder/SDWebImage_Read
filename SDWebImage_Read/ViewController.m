//
//  ViewController.m
//  SDWebImage_Read
//
//  Created by 孙春磊 on 2017/9/24.
//  Copyright © 2017年 云积分. All rights reserved.
//

#import "ViewController.h"
#import "UIImageView+WebCache.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIImageView *imageView2;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSMutableArray *urls = [NSMutableArray arrayWithCapacity:10];
    NSArray *urlStrings = @[
            @"http://pic.58pic.com/58pic/15/68/59/71X58PICNjx_1024.jpg",
            @"http://pic40.nipic.com/20140412/18428321_144447597175_2.jpg",
            @"http://pic32.nipic.com/20130823/13339320_183302468194_2.jpg"];
    
    [urlStrings enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [urls addObject:[NSURL URLWithString:obj]];
    }];
    NSURL *url = urls[1];
    
    
    // 加载同一张图片
    
    [_imageView setShowActivityIndicatorView:YES];
    [_imageView setBackgroundColor:[UIColor redColor]];
    [_imageView sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"sunchunlei.png"] options:SDWebImageRefreshCached];
    
    [_imageView2 setShowActivityIndicatorView:YES];
    [_imageView2 setBackgroundColor:[UIColor redColor]];
    [_imageView2 sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"sunchunlei.png"] options:SDWebImageRefreshCached progress:^(NSInteger receivedSize, NSInteger expectedSize) {
        NSLog(@"receivedSize:%d,expectedSize:%d",receivedSize,expectedSize);

    } completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
        NSLog(@"%@--%@",error,imageURL);

    }];
}
@end
