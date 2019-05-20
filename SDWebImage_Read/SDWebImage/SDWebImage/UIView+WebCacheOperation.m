/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "UIView+WebCacheOperation.h"
#import "objc/runtime.h"

static char loadOperationKey;

@implementation UIView (WebCacheOperation)

// 获取UIView对象的‘操作字典’: 字典的底层是用什么数据结构呢？可能是红黑树、哈希表等,效率很高
- (NSMutableDictionary *)operationDictionary {
    NSMutableDictionary *operations = objc_getAssociatedObject(self, &loadOperationKey);
    if (operations) {
        return operations;
    }
    operations = [NSMutableDictionary dictionary];
    // 为UIView对象添加了一个NSMutableDictionary变量: 用来记录图片下载操作
    objc_setAssociatedObject(self, &loadOperationKey, operations, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return operations;
    // 为什么要每个对象都携带一个operations字典呢? 是为了应对一个对象多次加载网络图片请求的场景？还有其他情况吗？
}

- (void)sd_setImageLoadOperation:(id)operation forKey:(NSString *)key {
    // 取消之前的操作: 相同的key时operation会被覆盖掉,在设置之前先将请求取消掉
    [self sd_cancelImageLoadOperationWithKey:key];
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    [operationDictionary setObject:operation forKey:key];
}

- (void)sd_cancelImageLoadOperationWithKey:(NSString *)key {
    // Cancel in progress downloader from queue
    // 获取对象的操作字典
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    // 获取字典中存储的某一个值
    id operations = [operationDictionary objectForKey:key];
    // 取消请求 从操作字典中移除该key
    if (operations) {
        if ([operations isKindOfClass:[NSArray class]]) {
            for (id <SDWebImageOperation> operation in operations) {
                if (operation) {
                    [operation cancel];
                }
            }
        } else if ([operations conformsToProtocol:@protocol(SDWebImageOperation)]){
            [(id<SDWebImageOperation>) operations cancel];
        }
        [operationDictionary removeObjectForKey:key];
    }
}

- (void)sd_removeImageLoadOperationWithKey:(NSString *)key {
    NSMutableDictionary *operationDictionary = [self operationDictionary];
    [operationDictionary removeObjectForKey:key];
}

@end
