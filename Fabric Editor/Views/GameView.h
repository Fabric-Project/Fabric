/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The header for the cross-platform game view.
*/

#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CAMetalDisplayLink.h>
#import <Metal/Metal.h>
#import "GameConfig.h"

#if TARGET_IOS || TARGET_TVOS
#import <UIKit/UIKit.h>
#define PlatformView UIView
#else
#import <AppKit/AppKit.h>
#define PlatformView NSView
#endif

// The protocol to provide resize and redraw callbacks to a delegate.
@protocol GameViewDelegate <NSObject>

- (void)drawableResize:(CGSize)size;

- (void)renderTo:(nonnull CAMetalLayer *)metalLayer
            with:(CAMetalDisplayLinkUpdate *_Nonnull)update
              at:(CFTimeInterval)deltaTime;

@end

// The Metal game view base class.
@interface GameView : PlatformView <CALayerDelegate, CAMetalDisplayLinkDelegate>

@property(nonatomic, nonnull, readonly) CAMetalLayer *metalLayer;

@property(nonatomic, getter=isPaused) BOOL paused;

@property(nonatomic, nullable) id<GameViewDelegate> delegate;

- (void)initCommon;

#if AUTOMATICALLY_RESIZE
- (void)resizeDrawable:(CGFloat)scaleFactor;
#endif

- (void)stopRenderLoop;

- (void)renderUpdate:(CAMetalDisplayLinkUpdate *_Nonnull)update
                with:(CFTimeInterval)deltaTime;

@end
