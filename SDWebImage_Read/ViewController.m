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

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    NSURL *url = [NSURL URLWithString:@"http://pic1.win4000.com/wallpaper/2/54811c7f4c396.jpg"];
    
    // 展示加载时的菊花
    [_imageView setShowActivityIndicatorView:YES];
    [_imageView sd_setImageWithURL:url placeholderImage:[UIImage imageNamed:@"sunchunlei.png"] options:SDWebImageProgressiveDownload | SDWebImageCacheMemoryOnly];

//    [_imageView sd_setImageWithURL:url completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
//        
//    }];
}


@end
