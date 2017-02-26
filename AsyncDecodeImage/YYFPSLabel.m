//
//  YYFPSLabel.m
//  AsyncDecodeImage
//
//  Created by kaibin on 17/2/26.
//  Copyright © 2017年 demo. All rights reserved.
//

#import "YYFPSLabel.h"
#import "YYWeakProxy.h"
#import <mach/mach.h>

#define kSize CGSizeMake(55*4, 20*2)

float cpu_usage()
{
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t      basic_info;
    thread_array_t         thread_list;
    mach_msg_type_number_t thread_count;
    
    thread_info_data_t     thinfo;
    mach_msg_type_number_t thread_info_count;
    
    thread_basic_info_t basic_info_th;
    uint32_t stat_thread = 0; // Mach threads
    
    basic_info = (task_basic_info_t)tinfo;
    
    // get threads in the task
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    if (thread_count > 0)
        stat_thread += thread_count;
    
    long tot_sec = 0;
    long tot_usec = 0;
    float tot_cpu = 0;
    int j;
    
    for (j = 0; j < thread_count; j++)
    {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[j], THREAD_BASIC_INFO,
                         (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            return -1;
        }
        
        basic_info_th = (thread_basic_info_t)thinfo;
        
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            tot_sec = tot_sec + basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
            tot_usec = tot_usec + basic_info_th->user_time.microseconds + basic_info_th->system_time.microseconds;
            tot_cpu = tot_cpu + basic_info_th->cpu_usage / (float)TH_USAGE_SCALE * 100.0;
        }
        
    } // for each thread
    
    kr = vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    assert(kr == KERN_SUCCESS);
    
    return tot_cpu;
}


@implementation YYFPSLabel {
    CADisplayLink *_link;
    NSUInteger _count;
    NSTimeInterval _lastTime;
    UIFont *_font;
    UIFont *_subFont;
    
    NSTimeInterval _llll;
}

static long curMemUsage = 0;

-(vm_size_t) usedMemory {
    struct task_basic_info info;
    mach_msg_type_number_t size = sizeof(info);
    kern_return_t kerr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size);
    return (kerr == KERN_SUCCESS) ? info.resident_size : 0; // size in bytes
}


- (instancetype)initWithFrame:(CGRect)frame {
    if (frame.size.width == 0 && frame.size.height == 0) {
        frame.size = kSize;
    }
    self = [super initWithFrame:frame];
    
    self.layer.cornerRadius = 5;
    self.clipsToBounds = YES;
    self.textAlignment = NSTextAlignmentCenter;
    self.userInteractionEnabled = NO;
    self.backgroundColor = [UIColor colorWithWhite:0.000 alpha:0.700];
    self.font = [UIFont systemFontOfSize:14.0];
    self.textColor = [UIColor yellowColor];
    
    _link = [CADisplayLink displayLinkWithTarget:[YYWeakProxy proxyWithTarget:self] selector:@selector(tick:)];
    [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    [self setup];
    return self;
}

- (void)setup
{
    self.userInteractionEnabled = YES;
    self.backgroundColor = [UIColor colorWithRed:0.0 green:0 blue:0 alpha:0.5];
    self.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] init];
    [pan addTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:pan];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan
{
    if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint location = [pan locationInView:self.superview];
        self.center = location;
    }
    else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGPoint location = [pan locationInView:self.superview];
        [self pinToEdge:location];
    }
}

- (void)pinToEdge:(CGPoint)location
{
    CGFloat x, y;
    UIViewAutoresizing mask;
    if (location.x <= CGRectGetMidX(self.superview.bounds)) {
        x = CGRectGetWidth(self.bounds) / 2;
        mask = UIViewAutoresizingFlexibleRightMargin;
    }
    else {
        x = CGRectGetMaxX(self.superview.bounds) - CGRectGetWidth(self.bounds) / 2;
        mask = UIViewAutoresizingFlexibleLeftMargin;
    }
    
    if (location.y <= CGRectGetMidY(self.superview.bounds)) {
        y = MAX(CGRectGetHeight(self.bounds) / 2, location.y);
        mask = mask | UIViewAutoresizingFlexibleBottomMargin;
    }
    else {
        y = MIN(CGRectGetMaxY(self.superview.bounds) - CGRectGetHeight(self.bounds) / 2, location.y);
        mask = mask | UIViewAutoresizingFlexibleTopMargin;
    }
    
    self.autoresizingMask = mask;
    
    [UIView animateWithDuration:.3 animations:^{
        self.center = CGPointMake(x, y);
    }];
}

- (void)dealloc {
    [_link invalidate];
}

- (CGSize)sizeThatFits:(CGSize)size {
    return kSize;
}

- (void)tick:(CADisplayLink *)link {
    if (_lastTime == 0) {
        _lastTime = link.timestamp;
        return;
    }
    
    _count++;
    NSTimeInterval delta = link.timestamp - _lastTime;
    if (delta < 1) return;
    _lastTime = link.timestamp;
    float fps = _count / delta;
    _count = 0;
    
    int printFps = (int)round(fps);
    int printCPUUsage = (int)ceil(cpu_usage());
    curMemUsage = [self usedMemory];
    NSString* content = [NSString stringWithFormat:@"%d FPS | CPU USAGE:%d%% | MEM USAGE:%luK", printFps, printCPUUsage, curMemUsage/1024];
     self.text = content;
}







@end
