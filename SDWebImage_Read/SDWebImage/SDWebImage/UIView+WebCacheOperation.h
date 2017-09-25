/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import <UIKit/UIKit.h>
#import "SDWebImageManager.h"

@interface UIView (WebCacheOperation)

/**
 *  Set the image load operation (storage in a UIView based dictionary)
 *  设置图像加载操作（存储在和UIView做绑定的字典里面）
 *  @param operation the operation
 *  @param key       key for storing the operation
 */
- (void)sd_setImageLoadOperation:(id)operation forKey:(NSString *)key;

/**
 *  Cancel all operations for the current UIView and key
 *  用这个key找到当前UIView上面的所有操作并取消
 *  @param key key for identifying the operations
 */
- (void)sd_cancelImageLoadOperationWithKey:(NSString *)key;

/**
 *  Just remove the operations corresponding to the current UIView and key without cancelling them
 *
 *  @param key key for identifying the operations
 */
- (void)sd_removeImageLoadOperationWithKey:(NSString *)key;

@end
