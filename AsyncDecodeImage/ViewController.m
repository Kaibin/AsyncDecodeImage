//
//  ViewController.m
//  AsyncDecodeImage
//
//  Created by kaibin on 17/2/26.
//  Copyright © 2017年 demo. All rights reserved.
//
/**
*   大尺寸图片帧动画解码
*   如果帧动画重复播放的频率不高，不需要考虑对原图或者对解码后位图数据做缓存
*/
#import "ViewController.h"
#import "YYWeakProxy.h"
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import "YYFPSLabel.h"
#import "AutoPurgeCache.h"

#define kFramesPerSecond 30
#define kImageCount 80

@interface ViewController ()

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, strong) UIButton *asyncButton;
@property (nonatomic, strong) UIButton *mainButton;
@property (nonatomic, strong) UIButton *mainButton2;
@property (nonatomic, strong) NSMutableArray *imageArray;
@property (nonatomic, strong) YYFPSLabel *fpsLabel;
@property (nonatomic, strong) NSCache *memCache;

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
    self.asyncButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.asyncButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.asyncButton setTitle:@"边解码边播放" forState:UIControlStateNormal];
    self.asyncButton.frame = CGRectMake(20, self.view.bounds.size.height - 100, 100, 40);
    [self.view addSubview:self.asyncButton];
    [self.asyncButton addTarget:self action:@selector(asyncPlay:) forControlEvents:UIControlEventTouchUpInside];
    
    self.mainButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mainButton.backgroundColor = [UIColor grayColor];
    self.mainButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.mainButton setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.mainButton setTitle:@"imageNamed" forState:UIControlStateNormal];
    self.mainButton.frame = CGRectMake(130, self.view.bounds.size.height - 100, 100, 40);
    [self.view addSubview:self.mainButton];
    [self.mainButton addTarget:self action:@selector(clickImageNamed:) forControlEvents:UIControlEventTouchUpInside];
    
    self.mainButton2 = [UIButton buttonWithType:UIButtonTypeCustom];
    self.mainButton2.backgroundColor = [UIColor grayColor];
    self.mainButton2.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.mainButton2 setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
    [self.mainButton2 setTitle:@"imageWithContentsOfFile" forState:UIControlStateNormal];
    self.mainButton2.frame = CGRectMake(240, self.view.bounds.size.height - 100, 120, 40);
    [self.view addSubview:self.mainButton2];
    [self.mainButton2 addTarget:self action:@selector(clickImageWithContentsOfFile:) forControlEvents:UIControlEventTouchUpInside];

    self.fpsLabel = [[YYFPSLabel alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 160, self.view.bounds.size.width, 30)];
    [self.view addSubview:self.fpsLabel];
    
    // Init the memory cache
    self.memCache = [[AutoPurgeCache alloc] init];
    self.memCache.name = @"memCache";
    self.memCache.totalCostLimit = 200*1024*1024;//200M
}

//帧动画图片数组
- (NSMutableArray *)imageArrayWithCache:(BOOL)cache
{
    if (!self.imageArray) {
        self.imageArray = [[NSMutableArray alloc] init];
        for (int i = 1; i <= kImageCount; i++) {
            NSString *fileName = [NSString stringWithFormat:@"gift_cupid_1_%d@2x", i];
            NSString *filePath = [[NSBundle mainBundle] pathForResource:fileName ofType:@"png"];
            UIImage *image;
            if (cache) {
                //系统会把图片和解码后位图数据缓存到内存，只有在内存低时才会被释放,
                image = [UIImage imageNamed:fileName];
            } else {
                //系统不会缓存原图片和解码后位图数据，每次加载图片都需要解码
                image = [UIImage imageWithContentsOfFile:filePath];
            }
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
    //加载图片后，不进行解码,也不缓存原图片,图像渲染前进行解码
//    UIImage *image = [UIImage imageWithContentsOfFile:filePath];
    UIImage *image = [self imageAtFilePath:filePath];
    [self decodeImage:image];
}

//通过ImageIO获取图像
- (UIImage *)imageAtFilePath:(NSString *)filePath
{
    //kCGImageSourceShouldCacheImmediately表示是否在加载完后立刻开始解码，默认为NO表示在渲染时才解码
    //kCGImageSourceShouldCache可以设置在图片的生命周期内，保存图片解码后的数据。64位设备默认为YES，32位设备默认为NO
    CFDictionaryRef options = (__bridge CFDictionaryRef)@{(__bridge id)kCGImageSourceShouldCacheImmediately:@(NO), (__bridge id)kCGImageSourceShouldCache:@(NO)};
    NSURL *imageURL = [NSURL fileURLWithPath:filePath];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)imageURL, NULL);
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(source, 0, options);//创建一个未解码的CGImage
    CGFloat scale = 1;
    if ([filePath rangeOfString:@"@2x"].location != NSNotFound) {
        scale = 2.0;
    }
    UIImage *image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];//此时图片还没有解码
    CGImageRelease(imageRef);
    CFRelease(source);
    return image;
}

- (void)clickImageNamed:(id)sender
{
    //会对解码后的图片位图数据缓存
    [self playAnimationImages:[self imageArrayWithCache:YES]];
}

- (void)clickImageWithContentsOfFile:(id)sender
{
    //不会对解码后的图片位图数据缓存
    [self playAnimationImages:[self imageArrayWithCache:NO]];
}

//使用animationImages属性播放帧动画，会导致内存暴增
- (void)playAnimationImages:(NSArray *)images
{
    self.imageView.animationDuration = kImageCount * 1./kFramesPerSecond;
    self.imageView.animationRepeatCount = 1;
    self.imageView.animationImages = images;//animationImages的copy属性会对images拷贝，使得images里面的图片retainCount都加1
    [self.imageView startAnimating];
    [self performSelector:@selector(didFinishAnimation) withObject:nil afterDelay:self.imageView.animationDuration];
}

//帧动画结束后
- (void)didFinishAnimation
{
    [self.imageArray removeAllObjects];
    self.imageArray = nil;
    self.imageView.animationImages = nil;//释放拷贝的images,images里面的图片retainCount减一释放内存
}

- (void)decodeImage:(UIImage *)image
{
    //异步线程图片解码
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CGImageRef decodedImage = decodeImageWithCGImage(image.CGImage, YES);//强制解码
        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.image = [UIImage imageWithCGImage:decodedImage scale:image.scale orientation:UIImageOrientationUp];
            CFRelease(decodedImage);
        });
    });
}

//返回解码后位图数据 Core Graphics offscreen rendering based on CPU
CGImageRef decodeImageWithCGImage(CGImageRef imageRef, BOOL decodeForDisplay)
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
        //先把图片绘制到 CGBitmapContext 中，然后从 Bitmap 直接创建图片
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

NSUInteger cacheCostForImage(UIImage *image) {
    return image.size.height * image.size.width * image.scale * image.scale;
}

@end
