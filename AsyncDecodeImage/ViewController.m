//
//  ViewController.m
//  AsyncDecodeImage
//
//  Created by kaibin on 17/2/26.
//  Copyright © 2017年 demo. All rights reserved.
//

#import "ViewController.h"
#import "YYWeakProxy.h"
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import "YYFPSLabel.h"

#define kFramesPerSecond 30
#define kImageCount 80

@interface ViewController ()

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, strong) UIButton *asyncButton;
@property (nonatomic, strong) UIButton *mainButton;
@property (nonatomic, strong) NSMutableArray *imageArray;
@property (nonatomic, strong) YYFPSLabel *fpsLabel;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    self.imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    self.imageView.contentMode = UIViewContentModeCenter;
    [self.view addSubview:self.imageView];
    
    self.asyncButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.asyncButton.backgroundColor = [UIColor grayColor];
    self.asyncButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.asyncButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.asyncButton setTitle:@"子线程解码" forState:UIControlStateNormal];
    self.asyncButton.frame = CGRectMake((self.view.bounds.size.width)/2-120, self.view.bounds.size.height - 100, 100, 40);
    [self.view addSubview:self.asyncButton];
    [self.asyncButton addTarget:self action:@selector(asyncPlay:) forControlEvents:UIControlEventTouchUpInside];
    
    self.mainButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mainButton.backgroundColor = [UIColor grayColor];
    self.mainButton.titleLabel.font = [UIFont systemFontOfSize:16];
    [self.mainButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.mainButton setTitle:@"主线程解码" forState:UIControlStateNormal];
    self.mainButton.frame = CGRectMake((self.view.bounds.size.width)/2+20, self.view.bounds.size.height - 100, 100, 40);
    [self.view addSubview:self.mainButton];
    [self.mainButton addTarget:self action:@selector(mainPlay:) forControlEvents:UIControlEventTouchUpInside];
    
    self.fpsLabel = [[YYFPSLabel alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 160, self.view.bounds.size.width, 30)];
    [self.view addSubview:self.fpsLabel];
}

//帧动画图片数组
- (NSMutableArray *)imageSequence
{
    if (!self.imageArray) {
        self.imageArray = [[NSMutableArray alloc] init];
        for (int i = 1; i <= kImageCount; i++) {
            NSString *fileName = [NSString stringWithFormat:@"gift_cupid_1_%d@2x", i];
            NSString *filePath = [[NSBundle mainBundle] pathForResource:fileName ofType:@"png"];
            UIImage *image = [UIImage imageWithContentsOfFile:filePath];
            if (image) {
                [self.imageArray addObject:image];
            }
        }
        
    }
    return self.imageArray;
}

//使用CADisplayLink不断刷新图像数据达到播放帧动画效果
- (void)asyncPlay:(id)sender
{
    self.displayLink = [CADisplayLink displayLinkWithTarget:[YYWeakProxy proxyWithTarget:self] selector:@selector(frameAnimation:)];
    self.displayLink.preferredFramesPerSecond = kFramesPerSecond;
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

//使用animationImages属性播放帧动画
- (void)mainPlay:(id)sender
{
    self.imageView.animationDuration = kImageCount * 1./kFramesPerSecond;
    self.imageView.animationRepeatCount = 1;
    self.imageView.animationImages = [self imageSequence];//解码后的位图数据都会保存在系统缓存下，只有在内存低之类的时候才会被释放
    [self.imageView startAnimating];
}

- (void)frameAnimation:(id)sender
{
    self.index++;
    if (self.index > kImageCount) {
        self.index = 0;
        [self.displayLink invalidate];
        self.displayLink = nil;
        return;
    };
    NSString *fileName = [NSString stringWithFormat:@"gift_cupid_1_%ld@2x", (long)self.index];
    NSString *filePath = [[NSBundle mainBundle] pathForResource:fileName ofType:@"png"];
    NSData *data = filePath ? [NSData dataWithContentsOfFile:filePath] : nil;//加载图片后，不进行解码,也不缓存原图片,图像渲染前进行解码
    if (!data) {
        return;
    }
    //子线程解码,耗cpu较高
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFTypeRef)data, NULL);//创建ImageSource
        //kCGImageSourceShouldCache=NO表示解码后不缓存，64位机器默认为YES，32位机器默认为NO
        //kCGImageSourceShouldCacheImmediately表示是否在加载完后立刻开始解码，这里我们要自己实现子线程解码所以设置NO
        CFDictionaryRef dic = (__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCache:@NO, (__bridge id)kCGImageSourceShouldCacheImmediately: @NO};
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, dic);//创建一个未解码的CGImage,解码后不缓存
        CGImageRef decodedImage = CGImageCreateDecodedCopy(image, YES);//解码
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.layer.contents = (__bridge id)decodedImage;
            self.imageView.layer.contentsScale = 2.0;//set the contentsScale to match image
            CFRelease(decodedImage);
            CFRelease(image);
            CFRelease(source);
        });
    });
}

//返回解码后位图数据
CGImageRef CGImageCreateDecodedCopy(CGImageRef imageRef, BOOL decodeForDisplay)
{
    if (!imageRef) return NULL;
    size_t width = CGImageGetWidth(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    if (width == 0 || height == 0) return NULL;
    
    if (decodeForDisplay) { //decode with redraw (may lose some precision)
        CGImageAlphaInfo alphaInfo = CGImageGetAlphaInfo(imageRef) & kCGBitmapAlphaInfoMask;
        BOOL hasAlpha = NO;
        if (alphaInfo == kCGImageAlphaPremultipliedLast ||
            alphaInfo == kCGImageAlphaPremultipliedFirst ||
            alphaInfo == kCGImageAlphaLast ||
            alphaInfo == kCGImageAlphaFirst) {
            hasAlpha = YES;
        }
        // BGRA8888 (premultiplied) or BGRX8888
        // same as UIGraphicsBeginImageContext() and -[UIView drawRect:]
        CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Host;
        bitmapInfo |= hasAlpha ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaNoneSkipFirst;
        CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, CGColorSpaceCreateDeviceRGB(), bitmapInfo);
        if (!context) return NULL;
        CGContextDrawImage(context, CGRectMake(0, 0, width, height), imageRef); // decode
        CGImageRef newImage = CGBitmapContextCreateImage(context);
        CFRelease(context);
        return newImage;
    } else {
        CGColorSpaceRef space = CGImageGetColorSpace(imageRef);
        size_t bitsPerComponent = CGImageGetBitsPerComponent(imageRef);
        size_t bitsPerPixel = CGImageGetBitsPerPixel(imageRef);
        size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
        CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(imageRef);
        if (bytesPerRow == 0 || width == 0 || height == 0) return NULL;
        
        CGDataProviderRef dataProvider = CGImageGetDataProvider(imageRef);
        if (!dataProvider) return NULL;
        CFDataRef data = CGDataProviderCopyData(dataProvider); // decode
        if (!data) return NULL;
        
        CGDataProviderRef newProvider = CGDataProviderCreateWithCFData(data);
        CFRelease(data);
        if (!newProvider) return NULL;
        
        CGImageRef newImage = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow, space, bitmapInfo, newProvider, NULL, false, kCGRenderingIntentDefault);
        CFRelease(newProvider);
        return newImage;
    }
}


@end
