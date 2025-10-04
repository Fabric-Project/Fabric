/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The implementation of the cross-platform game view.
*/

#import "GameView.h"
#import "GameConfig.h"

@implementation GameView
{
    CAMetalDisplayLink *_displayLink;
    CFTimeInterval _previousTargetPresentationTimestamp;
    
#if !RENDER_ON_MAIN_THREAD
    // The secondary thread containing the render loop.
    NSThread *_renderThread;
    
    // The flag to indicate that rendering needs to cease on the main thread.
    BOOL _continueRunLoop;
#endif
}

///////////////////////////////////////
#pragma mark - Initialization and Setup.
///////////////////////////////////////

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        [self initCommon];
    }
    return self;
}

- (void)initCommon
{
#if TARGET_MACOS
    self.wantsLayer = YES;
    
    self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
#endif
    
    _metalLayer = (CAMetalLayer*)self.layer;
    
    self.layer.delegate = self;
}

#if TARGET_IOS || TARGET_TVOS
+ (Class)layerClass
{
    return [CAMetalLayer class];
}

- (void)didMoveToWindow
{
    if (self.window == nil)
    {
        // If moving off of a window, destroy the display link.
        [_displayLink invalidate];
        _displayLink = nil;
        return;
    }
    
    [self movedToWindow];
}
#else
- (CALayer *)makeBackingLayer
{
    return [CAMetalLayer layer];
}

- (void)viewDidMoveToWindow
{
    [self movedToWindow];
}
#endif // END TARGET_IOS || TARGET_TVOS

- (void)movedToWindow
{
    // Guard..
    if ( self.window == nil) return;
    
    [self setupCAMetalLink];
    
#if RENDER_ON_MAIN_THREAD
    [self startMetalLink];
#else // IF !RENDER_ON_MAIN_THREAD
    // Protect _continueRunLoop with a `@synchronized` block because it's accessed by the separate
    // animation thread.
    @synchronized(self)
    {
        // Stop the animation loop, allowing it to complete if it's in progress.
        _continueRunLoop = NO;
    }
    
    // Create and start a secondary NSThread that has another run runloop. The NSThread
    // class calls the 'runThread' method at the start of the secondary thread's execution.
    _renderThread =  [[NSThread alloc] initWithTarget:self
                      selector:@selector(runThread)
                      object:nil];
    _continueRunLoop = YES;
    [_renderThread start];
#endif // END !RENDER_ON_MAIN_THREAD
    
    // Perform any actions that need to know the size and scale of the drawable. When UIKit calls
    // didMoveToWindow after the view initialization, this is the first opportunity to notify
    // components of the drawable's size.
#if AUTOMATICALLY_RESIZE
#if TARGET_IOS || TARGET_TVOS
    [self resizeDrawable:self.window.screen.nativeScale];
#else
    [self resizeDrawable:self.window.screen.backingScaleFactor];
#endif
#else
    // Notify the delegate of the default drawable size when the system can calculate it.
    CGSize defaultDrawableSize = self.bounds.size;
    defaultDrawableSize.width *= self.layer.contentsScale;
    defaultDrawableSize.height *= self.layer.contentsScale;
    [self.delegate drawableResize:defaultDrawableSize];
#endif
}

- (void)setupCAMetalLink
{
    [self stopRenderLoop];
    
    if ( self.metalLayer == nil)
    {
        [self initCommon];
    }
    
    [self makeMetalLink:self.metalLayer];
    
#if TARGET_MACOS
    // Register to receive a notification when the window closes so that you
    // can stop the display link.
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(windowWillClose:)
                               name:NSWindowWillCloseNotification
                             object:self.window];
#endif
}

#if TARGET_MACOS
- (void)windowWillClose:(NSNotification*)notification
{
    // Stop the display link when the window is closing because there's
    // no point in drawing something that you can't display.
    if (notification.object == self.window)
    {
        [self stopMetalLink];
    }
}
#endif // IF TARGET_MACOS

- (void)makeMetalLink:(nonnull CAMetalLayer *)metalLayer;
{
    // Create and configure the Metal display link.
    _displayLink = [[CAMetalDisplayLink alloc] initWithMetalLayer:metalLayer];
    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(120.0, 120.0, 120.0);
//    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(24, 24, 24);

    _displayLink.preferredFrameLatency = 1;
    _displayLink.paused = NO;
    // Assign the delegate to receive the display update callback.
    _displayLink.delegate = self;
}

//////////////////////////////////
#pragma mark - Render Loop Control
//////////////////////////////////

- (void)metalDisplayLink:(CAMetalDisplayLink *)link
             needsUpdate:(CAMetalDisplayLinkUpdate *_Nonnull)update
{
    CFTimeInterval deltaTime = _previousTargetPresentationTimestamp - update.targetPresentationTimestamp;
    _previousTargetPresentationTimestamp = update.targetPresentationTimestamp;
    
    [self renderUpdate:update with:deltaTime];
}

- (void)startMetalLink
{
    _previousTargetPresentationTimestamp = CACurrentMediaTime();
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop]
                       forMode:NSRunLoopCommonModes];
}

- (void)stopMetalLink
{
    [_displayLink removeFromRunLoop:[NSRunLoop mainRunLoop]
                            forMode:NSRunLoopCommonModes];
//    [_displayLink invalidate];
}

- (void)stopRenderLoop
{
    [_displayLink invalidate];
}

- (void)dealloc
{
    NSNotificationCenter* notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter removeObserver:self];
    
    _displayLink.delegate = nil;
    [self stopRenderLoop];
}

#if TARGET_IOS || TARGET_TVOS
- (void)setPaused:(BOOL)paused
{
    _paused = paused;
    
    _displayLink.paused = paused;
}

- (void)didEnterBackground:(NSNotification*)notification
{
    self.paused = YES;
}

- (void)willEnterForeground:(NSNotification*)notification
{
    self.paused = NO;
}
#endif

#if !RENDER_ON_MAIN_THREAD
- (void)runThread
{
    // Set the display link to the run loop of this thread so its callback occurs on this thread.
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [self startMetalLink];
    
    // The system sets the '_continueRunLoop' ivar outside this thread, so it needs to synchronize. Create a
    // 'continueRunLoop' local var that the system can set from the _continueRunLoop ivar in a @synchronized block.
    BOOL continueRunLoop = YES;
    
    // Begin the run loop.
    while (continueRunLoop)
    {
        // Create the autorelease pool for the current iteration of the loop.
        @autoreleasepool
        {
            // Run the loop once accepting input only from the display link.
            [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
        
        // Synchronize this with the _continueRunLoop ivar, which is set on another thread.
        @synchronized(self)
        {
            // When accessing anything outside the thread, such as the '_continueRunLoop' ivar,
            // the system reads it inside the synchronized block to ensure it writes fully/atomically.
            continueRunLoop = _continueRunLoop;
        }
    }
}
#endif // END !RENDER_ON_MAIN_THREAD

///////////////////////
#pragma mark - Resizing
///////////////////////

#if AUTOMATICALLY_RESIZE

// Override all methods that indicate the view's size has changed.

#if TARGET_IOS || TARGET_TVOS
- (void)setContentScaleFactor:(CGFloat)contentScaleFactor
{
    [super setContentScaleFactor:contentScaleFactor];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setFrame:(CGRect)frame
{
    [super setFrame:frame];
    [self resizeDrawable:self.window.screen.nativeScale];
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];
    [self resizeDrawable:self.window.screen.nativeScale];
}
#else
- (void)viewDidChangeBackingProperties
{
    [super viewDidChangeBackingProperties];
    [self resizeDrawable:self.window.screen.backingScaleFactor];
}

- (void)setFrameSize:(NSSize)size
{
    [super setFrameSize:size];
    [self resizeDrawable:self.window.screen.backingScaleFactor];
}

- (void)setBoundsSize:(NSSize)size
{
    [super setBoundsSize:size];
    [self resizeDrawable:self.window.screen.backingScaleFactor];
}
#endif

- (void)resizeDrawable:(CGFloat)scaleFactor
{
    CGSize newSize = self.bounds.size;
    newSize.width *= scaleFactor;
    newSize.height *= scaleFactor;
    
    if(newSize.width <= 0 || newSize.width <= 0)
    {
        return;
    }
    
#if RENDER_ON_MAIN_THREAD
    if(newSize.width == _metalLayer.drawableSize.width &&
       newSize.height == _metalLayer.drawableSize.height)
    {
        return;
    }
    
    _metalLayer.drawableSize = newSize;
    
    [_delegate drawableResize:newSize];
#else
    // The system calls all AppKit and UIKit calls that notify of a resize on the main thread. Use
    // a synchronized block to ensure that resize notifications on the delegate are atomic.
    @synchronized(_metalLayer)
    {
        if(newSize.width == _metalLayer.drawableSize.width &&
           newSize.height == _metalLayer.drawableSize.height)
        {
            return;
        }
        
        _metalLayer.drawableSize = newSize;
        
        [_delegate drawableResize:newSize];
    }
#endif
}
#endif // END AUTOMATICALLY_RESIZE

//////////////////////
#pragma mark - Drawing
//////////////////////

- (void)renderUpdate:(CAMetalDisplayLinkUpdate *_Nonnull)update
                with:(CFTimeInterval)deltaTime
{
#if RENDER_ON_MAIN_THREAD
    [_delegate renderTo:_metalLayer
                   with:update
                     at:deltaTime];
#else
    // You need to synchronize if rendering on the background thread to ensure resize operations from the
    // main thread are complete before any rendering that depends on the size occurs.
    @synchronized(_metalLayer)
    {
        [_delegate renderTo:_metalLayer
                       with:update
                         at:deltaTime];
    }
#endif
}

@end
