/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDWebImageDownloader.h"
#import "SDWebImageDownloaderOperation.h"
#import <ImageIO/ImageIO.h>

static NSString *const kProgressCallbackKey = @"progress";
static NSString *const kCompletedCallbackKey = @"completed";

// 封装的NSURLSession
@interface SDWebImageDownloader () <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>

@property (strong, nonatomic) NSOperationQueue *downloadQueue;
@property (weak, nonatomic) NSOperation *lastAddedOperation;
@property (assign, nonatomic) Class operationClass;
@property (strong, nonatomic) NSMutableDictionary *URLCallbacks;
// 保存headers
@property (strong, nonatomic) NSMutableDictionary *HTTPHeaders;

// This queue is used to serialize the handling of the network responses of all the download operation in a single queue
@property (SDDispatchQueueSetterSementics, nonatomic) dispatch_queue_t barrierQueue;

// The session in which data tasks will run
@property (strong, nonatomic) NSURLSession *session;

@end

// 内部封装了NSURLSession
@implementation SDWebImageDownloader

+ (void)initialize {
    // Bind SDNetworkActivityIndicator if available (download it here: http://github.com/rs/SDNetworkActivityIndicator )
    // To use it, just add #import "SDNetworkActivityIndicator.h" in addition to the SDWebImage import
    if (NSClassFromString(@"SDNetworkActivityIndicator")) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id activityIndicator = [NSClassFromString(@"SDNetworkActivityIndicator") performSelector:NSSelectorFromString(@"sharedActivityIndicator")];
#pragma clang diagnostic pop

        // Remove observer in case it was previously added.
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:activityIndicator name:SDWebImageDownloadStopNotification object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"startActivity")
                                                     name:SDWebImageDownloadStartNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:activityIndicator
                                                 selector:NSSelectorFromString(@"stopActivity")
                                                     name:SDWebImageDownloadStopNotification object:nil];
    }
}

+ (SDWebImageDownloader *)sharedDownloader {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (id)init {
    if ((self = [super init])) {
        // 默认值
        _operationClass = [SDWebImageDownloaderOperation class];
        
        _shouldDecompressImages = YES; // 默认解压图片
        _executionOrder = SDWebImageDownloaderFIFOExecutionOrder; // FIFO
        
        // 下载队列的默认配置
        _downloadQueue = [NSOperationQueue new];
        _downloadQueue.maxConcurrentOperationCount = 6; // 最大并发数
        _downloadQueue.name = @"com.hackemist.SDWebImageDownloader";
        
        // 字典: key是url value是个可变数组
        _URLCallbacks = [NSMutableDictionary new];
#ifdef SD_WEBP
        _HTTPHeaders = [@{@"Accept": @"image/webp,image/*;q=0.8"} mutableCopy];
#else
        _HTTPHeaders = [@{@"Accept": @"image/*;q=0.8"} mutableCopy];
#endif
        // 下载时用的并发队列
        _barrierQueue = dispatch_queue_create("com.hackemist.SDWebImageDownloaderBarrierQueue", DISPATCH_QUEUE_CONCURRENT);
        _downloadTimeout = 15.0; // 超时时间

        // NSURLSession配置
        NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
        sessionConfig.timeoutIntervalForRequest = _downloadTimeout;

        /** delegateQueue = nil
         The queue should be a serial queue, in order to ensure the correct ordering of callbacks. If nil, the session creates a serial operation queue for performing all delegate method calls and completion handler calls.
         */
        // 设置session的代理为self
        self.session = [NSURLSession sessionWithConfiguration:sessionConfig
                                                     delegate:self
                                                delegateQueue:nil];
        /**
         为什么代理遵守<NSURLSessionDelegate>这个基协议,但是在实现协议方法时实现了很多该协议的子协议呢？
         
         <NSURLSessionDelegate>协议说明
         
         A protocol defining methods that NSURLSession instances call on their delegates to handle session-level events, like session life cycle changes.
         Declaration
         
         @protocol NSURLSessionDelegate
         Discussion
         
         In addition to the methods defined in this protocol, most delegates should also implement some or all of the methods in the NSURLSessionTaskDelegate, NSURLSessionDataDelegate, and NSURLSessionDownloadDelegate protocols to handle task-level events. These include events like the beginning and end of individual tasks, and periodic progress updates from data or download tasks.
         Note
         Your NSURLSession object doesn’t need to have a delegate. If no delegate is assigned, a system-provided delegate is used, and you must provide a completion callback to obtain the data.

         
         
         
         
         方法说明
         + (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;

         Summary
         
         Creates a session with the specified session configuration, delegate, and operation queue.
         Declaration
         
         + (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration delegate:(id<NSURLSessionDelegate>)delegate delegateQueue:(NSOperationQueue *)queue;
         Parameters
         
         configuration
         A configuration object that specifies certain behaviors, such as caching policies, timeouts, proxies, pipelining, TLS versions to support, cookie policies, and credential storage.
         See NSURLSessionConfiguration for more information.
         delegate
         A session delegate object that handles requests for authentication and other session-related events.
         This delegate object is responsible for handling authentication challenges, for making caching decisions, and for handling other session-related events. If nil, the class should be used only with methods that take completion handlers.
         Important
         The session object keeps a strong reference to the delegate until your app exits or explicitly invalidates the session. If you do not invalidate the session by calling the invalidateAndCancel or finishTasksAndInvalidate method, your app leaks memory until it exits.
         queue
         An operation queue for scheduling the delegate calls and completion handlers. The queue should be a serial queue, in order to ensure the correct ordering of callbacks. If nil, the session creates a serial operation queue for performing all delegate method calls and completion handler calls.
         */
    }
    return self;
}

- (void)dealloc {
    [self.session invalidateAndCancel];
    self.session = nil;

    [self.downloadQueue cancelAllOperations];
    SDDispatchQueueRelease(_barrierQueue);
}

- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    if (value) {
        self.HTTPHeaders[field] = value;
    }
    else {
        [self.HTTPHeaders removeObjectForKey:field];
    }
}

- (NSString *)valueForHTTPHeaderField:(NSString *)field {
    return self.HTTPHeaders[field];
}

- (void)setMaxConcurrentDownloads:(NSInteger)maxConcurrentDownloads {
    _downloadQueue.maxConcurrentOperationCount = maxConcurrentDownloads;
}

- (NSUInteger)currentDownloadCount {
    return _downloadQueue.operationCount;
}

- (NSInteger)maxConcurrentDownloads {
    return _downloadQueue.maxConcurrentOperationCount;
}

- (void)setOperationClass:(Class)operationClass {
    _operationClass = operationClass ?: [SDWebImageDownloaderOperation class];
}

- (id <SDWebImageOperation>)downloadImageWithURL:(NSURL *)url options:(SDWebImageDownloaderOptions)options progress:(SDWebImageDownloaderProgressBlock)progressBlock completed:(SDWebImageDownloaderCompletedBlock)completedBlock {
    
    __block SDWebImageDownloaderOperation *operation;
    __weak __typeof(self)wself = self;
    
    /** 发方法主要做了以下处理
        1.记录url级别的各种回调
        2.并创建和配置operation
        3.将operation添加到downloadQueue(执行operation)
     */
    [self addProgressCallback:progressBlock completedBlock:completedBlock forURL:url createCallback:^{
        
        NSTimeInterval timeoutInterval = wself.downloadTimeout;
        if (timeoutInterval == 0.0) {
            timeoutInterval = 15.0;
        }
        
        /**
         NSURLCache 需要深入理解
         https://nshipster.com/nsurlcache/#response-cache-headers
         https://www.jianshu.com/p/aa49bb3555f4
         
         NSURLCache会默默的进行缓存的而且使用的是数据库
         NSURLCache只会对你的GET请求进行缓存
         
         NSURLRequestUseProtocolCachePolicy 按照协议(http)的缓存策略进行缓存
         缓存策略如下:
             服务器返回的响应头中会有这样的字段：Cache-Control: max-age or Cache-Control: s- maxage，通过Cache-Control来指定缓存策略，max-age来表示过期时间。根据这些字段缓存机制再采用如下策略：
         
             如果本地没有缓存数据，则进行网络请求。
             如果本地有缓存，并且缓存没有失效，则使用缓存。
             如果缓存已经失效，则询问服务器数据是否改变，如果没改变，依然使用缓存，如果改变了则请求新数据。
             如果没有指定是否失效，那么系统将自己判断缓存是否失效。（通常认为是6-24小时的有效时间）
         
         NSURLRequestReloadIgnoringLocalCacheData: Data should be loaded from the originating source. No existing cache data should be used. 不使用缓存
         
         */
        
        
        // 这层缓存是SD的内部的网络层缓存??
        // In order to prevent from potential duplicate caching (NSURLCache + SDImageCache) we disable the cache for image requests if told otherwise
        // 如果使用SDWebImageDownloaderUseNSURLCache则使用NSURLCache的缓存策略 否则忽略本地缓存(重新请求)

        // 创建请求
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:(options & SDWebImageDownloaderUseNSURLCache ? NSURLRequestUseProtocolCachePolicy : NSURLRequestReloadIgnoringLocalCacheData) timeoutInterval:timeoutInterval];
        
        request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies);
        request.HTTPShouldUsePipelining = YES;
        
        if (wself.headersFilter) {
            request.allHTTPHeaderFields = wself.headersFilter(url, [wself.HTTPHeaders copy]);
        }
        else {
            request.allHTTPHeaderFields = wself.HTTPHeaders;
        }
        
        // 创建并初始化请求操作---每次请求都会创建新的operation
        operation = [[wself.operationClass alloc]
                    initWithRequest:request
                    inSession:self.session
                    options:options
                    progress:^(NSInteger receivedSize, NSInteger expectedSize) {
                        
                         // 取出之前保存的进度回调并执行
                         SDWebImageDownloader *sself = wself;
                         if (!sself) return;
                         __block NSArray *callbacksForURL;
                        
                         dispatch_sync(sself.barrierQueue, ^{
                             callbacksForURL = [sself.URLCallbacks[url] copy];
                         });
                         for (NSDictionary *callbacks in callbacksForURL) {
                             dispatch_async(dispatch_get_main_queue(), ^{
                                 SDWebImageDownloaderProgressBlock callback = callbacks[kProgressCallbackKey];
                                 if (callback) callback(receivedSize, expectedSize);
                             });
                         }
                     }
                    completed:^(UIImage *image, NSData *data, NSError *error, BOOL finished) {
                        // 取出之前保存的完成回调并执行
                        SDWebImageDownloader *sself = wself;
                        if (!sself) return;
                        __block NSArray *callbacksForURL;
                        dispatch_barrier_sync(sself.barrierQueue, ^{
                            callbacksForURL = [sself.URLCallbacks[url] copy];
                            if (finished) {
                                [sself.URLCallbacks removeObjectForKey:url];
                            }
                        });
                        for (NSDictionary *callbacks in callbacksForURL) {
                            SDWebImageDownloaderCompletedBlock callback = callbacks[kCompletedCallbackKey];
                            if (callback) callback(image, data, error, finished);
                        }
                    }
                    cancelled:^{
                            // 删除这个url的回调
                            SDWebImageDownloader *sself = wself;
                            if (!sself) return;
                            dispatch_barrier_async(sself.barrierQueue, ^{
                                [sself.URLCallbacks removeObjectForKey:url];
                            });
                        }
                     ];
        
        // 是否解压图片
        operation.shouldDecompressImages = wself.shouldDecompressImages;
        
        // 验证证书相关
        if (wself.urlCredential) {
            operation.credential = wself.urlCredential;
        } else if (wself.username && wself.password) {
            operation.credential = [NSURLCredential credentialWithUser:wself.username password:wself.password persistence:NSURLCredentialPersistenceForSession];
        }
        
        // 下载优先级
        if (options & SDWebImageDownloaderHighPriority) {
            operation.queuePriority = NSOperationQueuePriorityHigh;
        } else if (options & SDWebImageDownloaderLowPriority) {
            operation.queuePriority = NSOperationQueuePriorityLow;
        }

        // 将operation添加到NSOperationQueue即开始执行任务了
        [wself.downloadQueue addOperation:operation];
        
        if (wself.executionOrder == SDWebImageDownloaderLIFOExecutionOrder) {
            // Emulate LIFO execution order by systematically adding new operations as last operation's dependency
            // 如果是LIFO模式 那么让先operation依赖后加入operation 以达到后进先出(LIFO)的效果
            [wself.lastAddedOperation addDependency:operation];
            // 记录上一个operation
            wself.lastAddedOperation = operation;
            
            /**
             addDependency方法说明:
             The receiver is not considered ready to execute until all of its dependent operations have finished executing. If the receiver is already executing its task, adding dependencies has no practical effect. This method may change the isReady and dependencies properties of the receiver.
             */
        }
    }];

    return operation;
}

- (void)addProgressCallback:(SDWebImageDownloaderProgressBlock)progressBlock completedBlock:(SDWebImageDownloaderCompletedBlock)completedBlock forURL:(NSURL *)url createCallback:(SDWebImageNoParamsBlock)createCallback {
    
    // The URL will be used as the key to the callbacks dictionary so it cannot be nil. If it is nil immediately call the completed block with no image or data.
    if (url == nil) {
        if (completedBlock != nil) {
            completedBlock(nil, nil, nil, NO);
        }
        return;
    }

    // 使用dispatch_barrier_sync保证这段操作不会出现并发 任务按顺序执行
    dispatch_barrier_sync(self.barrierQueue, ^{
        
        BOOL first = NO;
        if (!self.URLCallbacks[url]) {
            self.URLCallbacks[url] = [NSMutableArray new];
            first = YES;
        }

        // Handle single download of simultaneous(同时) download request for the same URL
        
        // 回调数组
        NSMutableArray *callbacksForURL = self.URLCallbacks[url];
        // 存放回调的字典
        NSMutableDictionary *callbacks = [NSMutableDictionary new];
        if (progressBlock) callbacks[kProgressCallbackKey] = [progressBlock copy];
        if (completedBlock) callbacks[kCompletedCallbackKey] = [completedBlock copy];
        // 将回调添加到数组
        [callbacksForURL addObject:callbacks];
        // 每个url都对应了一个回调数组 数组中存放着回调
        self.URLCallbacks[url] = callbacksForURL;
        
        //  同一个url仅仅在第一次来时调用 createCallback即可,createCallback中会发起下载
        if (first) {
            createCallback();
        }
        
        /**
         为什么这么设计呢?
         多个imageView可能加载同一个url,这样会出现一个url会有多个回调。 使用这种方式将回调保存到数组中。
         
         测试:两个imageView下载同一个url的情况
         URLCallbacks中存放的信息
         {
             "http://pic40.nipic.com/20140412/18428321_144447597175_2.jpg" =     (
                     {
                         completed = "<__NSMallocBlock__: 0x60000020f300>";
                     },
                     {
                         completed = "<__NSMallocBlock__: 0x60000021d200>";
                         progress = "<__NSGlobalBlock__: 0x105353240>";
                     }
             );
         }
         */

    });
    
    /**
     dispatch_barrier_sync 说明
     
     Submits a barrier block to a dispatch queue for synchronous execution. Unlike dispatch_barrier_async, this function does not return until the barrier block has finished. Calling this function and targeting the current queue results in deadlock.
     When the barrier block reaches the front of a private concurrent queue, it is not executed immediately. Instead, the queue waits until its currently executing blocks finish executing. At that point, the queue executes the barrier block by itself. Any blocks submitted after the barrier block are not executed until the barrier block completes.
     The queue you specify should be a concurrent queue that you create yourself using the dispatch_queue_create function. If the queue you pass to this function is a serial queue or one of the global concurrent queues, this function behaves like the dispatch_sync function.
     Unlike with dispatch_barrier_async, no retain is performed on the target queue. Because calls to this function are synchronous, it "borrows" the reference of the caller. Moreover, no Block_copy is performed on the block.
     As an optimization, this function invokes the barrier block on the current thread when possible.
     */
}

- (void)setSuspended:(BOOL)suspended {
    [self.downloadQueue setSuspended:suspended];
}

- (void)cancelAllDownloads {
    [self.downloadQueue cancelAllOperations];
}

#pragma mark Helper methods
// 通过dataTask.taskIdentifier找到对应的operation
- (SDWebImageDownloaderOperation *)operationWithTask:(NSURLSessionTask *)task {
    
    SDWebImageDownloaderOperation *returnOperation = nil;
    for (SDWebImageDownloaderOperation *operation in self.downloadQueue.operations) {
        if (operation.dataTask.taskIdentifier == task.taskIdentifier) {
            returnOperation = operation;
            break;
        }
    }
    return returnOperation;
}


// 将代理方法转发给通过dataTask找到的operation

#pragma mark NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];
    [dataOperation URLSession:session dataTask:dataTask didReceiveResponse:response completionHandler:completionHandler];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
 willCacheResponse:(NSCachedURLResponse *)proposedResponse
 completionHandler:(void (^)(NSCachedURLResponse *cachedResponse))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:dataTask];

    [dataOperation URLSession:session dataTask:dataTask willCacheResponse:proposedResponse completionHandler:completionHandler];
}

#pragma mark NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didCompleteWithError:error];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {

    // Identify the operation that runs this task and pass it the delegate method
    SDWebImageDownloaderOperation *dataOperation = [self operationWithTask:task];

    [dataOperation URLSession:session task:task didReceiveChallenge:challenge completionHandler:completionHandler];
}

@end
