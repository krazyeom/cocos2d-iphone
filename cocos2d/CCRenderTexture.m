/*
 * cocos2d for iPhone: http://www.cocos2d-iphone.org
 *
 * Copyright (c) 2009 Jason Booth
 * Copyright (c) 2013-2014 Cocos2D Authors
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

#import "CCRenderTexture.h"
#import "CCDirector.h"
#import "ccMacros.h"
#import "CCShader.h"
#import "CCConfiguration.h"
#import "Support/ccUtils.h"
#import "Support/CCFileUtils.h"
#import "Support/CGPointExtension.h"

#import "CCTexture_Private.h"
#import "CCDirector_Private.h"
#import "CCNode_Private.h"
#import "CCRenderer_private.h"
#import "OpenGL_Internal.h"

#if __CC_PLATFORM_MAC
#import <ApplicationServices/ApplicationServices.h>
#endif

@implementation CCRenderTexture {
	GLKMatrix4 _oldProjection;
}

@synthesize sprite=_sprite;
@synthesize autoDraw=_autoDraw;
@synthesize clearDepth=_clearDepth;
@synthesize clearStencil=_clearStencil;
@synthesize clearFlags=_clearFlags;

+(id)renderTextureWithWidth:(int)w height:(int)h pixelFormat:(CCTexturePixelFormat) format depthStencilFormat:(GLuint)depthStencilFormat
{
  return [[self alloc] initWithWidth:w height:h pixelFormat:format depthStencilFormat:depthStencilFormat];
}

// issue #994
+(id)renderTextureWithWidth:(int)w height:(int)h pixelFormat:(CCTexturePixelFormat) format
{
	return [[self alloc] initWithWidth:w height:h pixelFormat:format];
}

+(id)renderTextureWithWidth:(int)w height:(int)h
{
	return [[self alloc] initWithWidth:w height:h pixelFormat:CCTexturePixelFormat_RGBA8888 depthStencilFormat:0];
}

-(id)initWithWidth:(int)w height:(int)h
{
	return [self initWithWidth:w height:h pixelFormat:CCTexturePixelFormat_RGBA8888];
}

- (id)initWithWidth:(int)w height:(int)h pixelFormat:(CCTexturePixelFormat)format
{
  return [self initWithWidth:w height:h pixelFormat:format depthStencilFormat:0];
}

-(id)initWithWidth:(int)w height:(int)h pixelFormat:(CCTexturePixelFormat) format depthStencilFormat:(GLuint)depthStencilFormat
{
	if ((self = [super init]))
	{
		NSAssert(format != CCTexturePixelFormat_A8,@"only RGB and RGBA formats are valid for a render texture");

		CCDirector *director = [CCDirector sharedDirector];

		// XXX multithread
		if( [director runningThread] != [NSThread currentThread] )
			CCLOGWARN(@"cocos2d: WARNING. CCRenderTexture is running on its own thread. Make sure that an OpenGL context is being used on this thread!");

		CGFloat scale = [CCDirector sharedDirector].contentScaleFactor;
		w *= scale;
		h *= scale;

		glGetIntegerv(GL_FRAMEBUFFER_BINDING, &_oldFBO);

		// textures must be power of two
		NSUInteger powW;
		NSUInteger powH;

		if( [[CCConfiguration sharedConfiguration] supportsNPOT] ) {
			powW = w;
			powH = h;
		} else {
			powW = CCNextPOT(w);
			powH = CCNextPOT(h);
		}

		void *data = malloc((int)(powW * powH * 4));
		memset(data, 0, (int)(powW * powH * 4));
		_pixelFormat=format;

		self.texture = [[CCTexture alloc] initWithData:data pixelFormat:_pixelFormat pixelsWide:powW pixelsHigh:powH contentSizeInPixels:CGSizeMake(w, h) contentScale:[CCDirector sharedDirector].contentScaleFactor];
		free( data );

		GLint oldRBO;
		glGetIntegerv(GL_RENDERBUFFER_BINDING, &oldRBO);

		// generate FBO
		glGenFramebuffers(1, &_FBO);
		glBindFramebuffer(GL_FRAMEBUFFER, _FBO);

		// associate texture with FBO
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self.texture.name, 0);

		if (depthStencilFormat != 0) {
			//create and attach depth buffer
			glGenRenderbuffers(1, &_depthRenderBufffer);
			glBindRenderbuffer(GL_RENDERBUFFER, _depthRenderBufffer);
			glRenderbufferStorage(GL_RENDERBUFFER, depthStencilFormat, (GLsizei)powW, (GLsizei)powH);
			glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBufffer);

			// if depth format is the one with stencil part, bind same render buffer as stencil attachment
			if (depthStencilFormat == GL_DEPTH24_STENCIL8)
				glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, _depthRenderBufffer);
		}

		// check if it worked (probably worth doing :) )
		NSAssert( glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, @"Could not attach texture to framebuffer");

		[self.texture setAliasTexParameters];

		// retained
		self.sprite = [CCSprite spriteWithTexture:self.texture];

		[_sprite setScaleY:-1];

		// issue #937
		_sprite.blendMode = [CCBlendMode premultipliedAlphaMode];
		// issue #1464
		[_sprite setOpacityModifyRGB:YES];

		glBindRenderbuffer(GL_RENDERBUFFER, oldRBO);
		glBindFramebuffer(GL_FRAMEBUFFER, _oldFBO);
		
		CHECK_GL_ERROR_DEBUG();
		
		// Diabled by default.
		_autoDraw = NO;
		
		// add sprite for backward compatibility
		[self addChild:_sprite];
	}
	return self;
}

-(void)dealloc
{
	glDeleteFramebuffers(1, &_FBO);
	if(_depthRenderBufffer){
		glDeleteRenderbuffers(1, &_depthRenderBufffer);
	}
}

//-(void)begin
//{
//	CCDirector *director = [CCDirector sharedDirector];
//	
//	// #warning Should probably move the projection matrix to the renderer?
//	_oldProjection = director.projectionMatrix;;
//  
//	[director setProjection:director.projection];
//  
//	CGSize texSize = [_texture contentSizeInPixels];
//
//
//	// Calculate the adjustment ratios based on the old and new projections
//	CGSize size = [director viewSizeInPixels];
//	float widthRatio = size.width / texSize.width;
//	float heightRatio = size.height / texSize.height;
//
//
//	// Adjust the orthographic projection and viewport
//	glViewport(0, 0, texSize.width, texSize.height );
//
//	#warning This is silly. It should just set a new projection not adjust the old one.
////	kmMat4 orthoMatrix;
////	kmMat4OrthographicProjection(&orthoMatrix, (float)-1.0 / widthRatio,  (float)1.0 / widthRatio,
////								 (float)-1.0 / heightRatio, (float)1.0 / heightRatio, -1,1 );
////	kmGLMultMatrix(&orthoMatrix);
//	director.projectionMatrix = GLKMatrix4Multiply(_oldProjection, GLKMatrix4MakeOrtho(
//		-1.0 / widthRatio,  1.0 / widthRatio, -1.0 / heightRatio, 1.0 / heightRatio, -1, 1
//	));
//  
//
//	glGetIntegerv(GL_FRAMEBUFFER_BINDING, &_oldFBO);
//	glBindFramebuffer(GL_FRAMEBUFFER, _FBO);
//}
//
//-(void)beginWithClear:(float)r g:(float)g b:(float)b a:(float)a depth:(float)depthValue stencil:(int)stencilValue flags:(GLbitfield)flags
//{
//	[self begin];
//	
//	// save clear color
//	GLfloat	clearColor[4];
//	GLfloat depthClearValue;
//	int stencilClearValue;
//	
//	if(flags & GL_COLOR_BUFFER_BIT) {
//		glGetFloatv(GL_COLOR_CLEAR_VALUE,clearColor);
//		glClearColor(r, g, b, a);
//	}
//	
//	if( flags & GL_DEPTH_BUFFER_BIT ) {
//		glGetFloatv(GL_DEPTH_CLEAR_VALUE, &depthClearValue);
//		glClearDepth(depthValue);
//	}
//	
//	if( flags & GL_STENCIL_BUFFER_BIT ) {
//		glGetIntegerv(GL_STENCIL_CLEAR_VALUE, &stencilClearValue);
//		glClearStencil(stencilValue);
//	}
//	
//	glClear(flags);
//	
//	
//	// restore
//	if( flags & GL_COLOR_BUFFER_BIT)
//		glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
//	if( flags & GL_DEPTH_BUFFER_BIT)
//		glClearDepth(depthClearValue);
//	if( flags & GL_STENCIL_BUFFER_BIT)
//		glClearStencil(stencilClearValue);
//}
//
//-(void)beginWithClear:(float)r g:(float)g b:(float)b a:(float)a
//{
//	[self beginWithClear:r g:g b:b a:a depth:0 stencil:0 flags:GL_COLOR_BUFFER_BIT];
//}
//
//-(void)beginWithClear:(float)r g:(float)g b:(float)b a:(float)a depth:(float)depthValue
//{
//	[self beginWithClear:r g:g b:b a:a depth:depthValue stencil:0 flags:GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT];
//}
//-(void)beginWithClear:(float)r g:(float)g b:(float)b a:(float)a depth:(float)depthValue stencil:(int)stencilValue
//{
//	[self beginWithClear:r g:g b:b a:a depth:depthValue stencil:stencilValue flags:GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT|GL_STENCIL_BUFFER_BIT];
//}
//
//-(void)end
//{
//	CCDirector *director = [CCDirector sharedDirector];
//	glBindFramebuffer(GL_FRAMEBUFFER, _oldFBO);
//
//	// restore viewport
//	[director setViewport];
//	
//	director.projectionMatrix = _oldProjection;
//}
//
//-(void)clear:(float)r g:(float)g b:(float)b a:(float)a
//{
//	[self beginWithClear:r g:g b:b a:a];
//	[self end];
//}
//
//- (void)clearDepth:(float)depthValue
//{
//	[self begin];
//	//! save old depth value
//	GLfloat depthClearValue;
//	glGetFloatv(GL_DEPTH_CLEAR_VALUE, &depthClearValue);
//
//	glClearDepth(depthValue);
//	glClear(GL_DEPTH_BUFFER_BIT);
//
//	// restore clear color
//	glClearDepth(depthClearValue);
//	[self end];
//}
//
//- (void)clearStencil:(int)stencilValue
//{
//	// save old stencil value
//	int stencilClearValue;
//	glGetIntegerv(GL_STENCIL_CLEAR_VALUE, &stencilClearValue);
//
//	glClearStencil(stencilValue);
//	glClear(GL_STENCIL_BUFFER_BIT);
//
//	// restore clear color
//	glClearStencil(stencilClearValue);
//}

-(void)render:(void (^)(CCRenderer *, GLKMatrix4 *))block
{
//	GLfloat	oldClearColor[4];
//	if(_clearFlags & GL_COLOR_BUFFER_BIT){
//		glGetFloatv(GL_COLOR_CLEAR_VALUE, oldClearColor);
//		glClearColor(_clearColor.r, _clearColor.g, _clearColor.b, _clearColor.a);
//	}
//	
//	GLfloat oldDepthClearValue;
//	if(_clearFlags & GL_DEPTH_BUFFER_BIT){
//		glGetFloatv(GL_DEPTH_CLEAR_VALUE, &oldDepthClearValue);
//		glClearDepth(_clearDepth);
//	}
//	
//	int stencilClearValue;
//	if(_clearFlags & GL_STENCIL_BUFFER_BIT){
//		glGetIntegerv(GL_STENCIL_CLEAR_VALUE, &oldStencilClearValue);
//		glClearStencil(_clearStencil);
//	}
//	
//	glClear(_clearFlags);
//	
//	
//	// restore
//	if( flags & GL_COLOR_BUFFER_BIT)
//		glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
//	if( flags & GL_DEPTH_BUFFER_BIT)
//		glClearDepth(depthClearValue);
//	if( flags & GL_STENCIL_BUFFER_BIT)
//		glClearStencil(stencilClearValue);
	
	CGSize texSize = [self.texture contentSizeInPixels];
	GLKMatrix4 projection = GLKMatrix4MakeOrtho(0.0f, texSize.width/__ccContentScaleFactor, 0.0f, texSize.height/__ccContentScaleFactor, -1024.0f, 1024.0f);
	
	__block struct{ GLfloat v[4]; } oldViewport;
	
	CCRenderer *renderer = [CCRenderer currentRenderer];
	BOOL needsFlush = NO;
	
	if(renderer == nil){
		renderer = [[CCRenderer alloc] init];
		
		NSMutableDictionary *uniforms = [[CCDirector sharedDirector].globalShaderUniforms mutableCopy];
		uniforms[CCShaderUniformProjection] = [NSValue valueWithGLKMatrix4:projection];
		renderer.globalShaderUniforms = uniforms;
		
		[CCRenderer bindRenderer:renderer];
		needsFlush = YES;
	} else {
		#warning TODO update projection
	}
	
	[renderer customGLBlock:^{
		glGetFloatv(GL_VIEWPORT, oldViewport.v);
		glViewport(0, 0, texSize.width, texSize.height );
		
		glGetIntegerv(GL_FRAMEBUFFER_BINDING, &_oldFBO);
		glBindFramebuffer(GL_FRAMEBUFFER, _FBO);
		
		glClear(GL_COLOR_BUFFER_BIT);
	}];

	block(renderer, &projection);
	
	[renderer customGLBlock:^{
		glBindFramebuffer(GL_FRAMEBUFFER, _oldFBO);
		glViewport(oldViewport.v[0], oldViewport.v[1], oldViewport.v[2], oldViewport.v[3]);
	}];
	
	if(needsFlush){
		[renderer flush];
		[CCRenderer bindRenderer:nil];
	}
}

#pragma mark RenderTexture - "auto" update

- (void)visit:(CCRenderer *)renderer parentTransform:(const GLKMatrix4 *)parentTransform
{
	// override visit.
	// Don't call visit on its children
	if (!_visible)
		return;
	
	GLKMatrix4 transform = [self transform:parentTransform];
	[_sprite visit:renderer parentTransform:&transform];
	[self draw:renderer transform:&transform];
	
	_orderOfArrival = 0;
}

- (void)draw:(CCRenderer *)_renderer transform:(const GLKMatrix4 *)_transform
{
	if( _autoDraw) {
		
//		[self begin];
//		
//		if (_clearFlags) {
//			
//			GLfloat oldClearColor[4];
//			GLfloat oldDepthClearValue;
//			GLint oldStencilClearValue;
//			
//			// backup and set
//			if( _clearFlags & GL_COLOR_BUFFER_BIT ) {
//				glGetFloatv(GL_COLOR_CLEAR_VALUE, oldClearColor);
//				glClearColor(_clearColor.r, _clearColor.g, _clearColor.b, _clearColor.a);
//			}
//			
//			if( _clearFlags & GL_DEPTH_BUFFER_BIT ) {
//				glGetFloatv(GL_DEPTH_CLEAR_VALUE, &oldDepthClearValue);
//				glClearDepth(_clearDepth);
//			}
//			
//			if( _clearFlags & GL_STENCIL_BUFFER_BIT ) {
//				glGetIntegerv(GL_STENCIL_CLEAR_VALUE, &oldStencilClearValue);
//				glClearStencil(_clearStencil);
//			}
//			
//			// clear
//			glClear(_clearFlags);
//			
//			// restore
//			if( _clearFlags & GL_COLOR_BUFFER_BIT )
//				glClearColor(oldClearColor[0], oldClearColor[1], oldClearColor[2], oldClearColor[3]);
//			if( _clearFlags & GL_DEPTH_BUFFER_BIT )
//				glClearDepth(oldDepthClearValue);
//			if( _clearFlags & GL_STENCIL_BUFFER_BIT )
//				glClearStencil(oldStencilClearValue);
//		}
		
		//! make sure all children are drawn
		[self sortAllChildren];
		
		[self render:^(CCRenderer *renderer, GLKMatrix4 *transform) {
			for (CCNode *child in _children) {
				if( child != _sprite) [child visit:renderer parentTransform:transform];
			}
		}];
		
//		[self end];
	}

//	[_sprite visit];
}

#pragma mark RenderTexture - Save Image

-(CGImageRef) newCGImage
{
    NSAssert(_pixelFormat == CCTexturePixelFormat_RGBA8888,@"only RGBA8888 can be saved as image");
	
	
	CGSize s = [self.texture contentSizeInPixels];
	int tx = s.width;
	int ty = s.height;
	
	int bitsPerComponent			= 8;
    int bitsPerPixel                = 4 * 8;
    int bytesPerPixel               = bitsPerPixel / 8;
	int bytesPerRow					= bytesPerPixel * tx;
	NSInteger myDataLength			= bytesPerRow * ty;
	
	GLubyte *buffer	= calloc(myDataLength,1);
	GLubyte *pixels	= calloc(myDataLength,1);
	
	
	if( ! (buffer && pixels) ) {
		CCLOG(@"cocos2d: CCRenderTexture#getCGImageFromBuffer: not enough memory");
		free(buffer);
		free(pixels);
		return nil;
	}
	
	#warning TODO
//	[self begin];
//	
//
//	glReadPixels(0,0,tx,ty,GL_RGBA,GL_UNSIGNED_BYTE, buffer);
//
//	[self end];
	
	// make data provider with data.
	
	CGBitmapInfo bitmapInfo	= kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault;
	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer, myDataLength, NULL);
	CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
	CGImageRef iref	= CGImageCreate(tx, ty,
									bitsPerComponent, bitsPerPixel, bytesPerRow,
									colorSpaceRef, bitmapInfo, provider,
									NULL, false,
									kCGRenderingIntentDefault);
	
	CGContextRef context = CGBitmapContextCreate(pixels, tx,
												 ty, CGImageGetBitsPerComponent(iref),
												 CGImageGetBytesPerRow(iref), CGImageGetColorSpace(iref),
												 bitmapInfo);
	
	// vertically flipped
	if( YES ) {
		CGContextTranslateCTM(context, 0.0f, ty);
		CGContextScaleCTM(context, 1.0f, -1.0f);
	}
	CGContextDrawImage(context, CGRectMake(0.0f, 0.0f, tx, ty), iref);
	CGImageRef image = CGBitmapContextCreateImage(context);
	
	CGContextRelease(context);
	CGImageRelease(iref);
	CGColorSpaceRelease(colorSpaceRef);
	CGDataProviderRelease(provider);
	
	free(pixels);
	free(buffer);
	
	return image;
}

-(BOOL) saveToFile:(NSString*)name
{
	return [self saveToFile:name format:CCRenderTextureImageFormatJPEG];
}

-(BOOL)saveToFile:(NSString*)fileName format:(CCRenderTextureImageFormat)format
{
	BOOL success;
	
	NSString *fullPath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:fileName];
	
	CGImageRef imageRef = [self newCGImage];

	if( ! imageRef ) {
		CCLOG(@"cocos2d: Error: Cannot create CGImage ref from texture");
		return NO;
	}
	
#if __CC_PLATFORM_IOS
	CGFloat scale = [CCDirector sharedDirector].contentScaleFactor;
	UIImage* image	= [[UIImage alloc] initWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
	NSData *imageData = nil;
    
	if( format == CCRenderTextureImageFormatPNG )
		imageData = UIImagePNGRepresentation( image );
    
	else if( format == CCRenderTextureImageFormatJPEG )
		imageData = UIImageJPEGRepresentation(image, 0.9f);
    
	else
		NSAssert(NO, @"Unsupported format");
	
    
	success = [imageData writeToFile:fullPath atomically:YES];

	
#elif __CC_PLATFORM_MAC
	
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:fullPath];
	
	CGImageDestinationRef dest;

	if( format == CCRenderTextureImageFormatPNG )
		dest = 	CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);

	else if( format == CCRenderTextureImageFormatJPEG )
		dest = 	CGImageDestinationCreateWithURL(url, kUTTypeJPEG, 1, NULL);

	else
		NSAssert(NO, @"Unsupported format");

	CGImageDestinationAddImage(dest, imageRef, nil);
		
	success = CGImageDestinationFinalize(dest);

	CFRelease(dest);
#endif

	CGImageRelease(imageRef);
	
	if( ! success )
		CCLOG(@"cocos2d: ERROR: Failed to save file:%@ to disk",fullPath);

	return success;
}


#if __CC_PLATFORM_IOS

-(UIImage *) getUIImage
{
	CGImageRef imageRef = [self newCGImage];
	
	CGFloat scale = [CCDirector sharedDirector].contentScaleFactor;
	UIImage* image	= [[UIImage alloc] initWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
    
	CGImageRelease( imageRef );
    
	return image;
}
#endif // __CC_PLATFORM_IOS

- (CCColor*) clearColor
{
    return [CCColor colorWithCcColor4f:_clearColor];
}

- (void) setClearColor:(CCColor *)clearColor
{
    _clearColor = clearColor.ccColor4f;
}

#pragma RenderTexture - Override

-(CGSize) contentSize
{
	return self.texture.contentSize;
}

-(void) setContentSize:(CGSize)size
{
	NSAssert(NO, @"You cannot change the content size of an already created CCRenderTexture. Recreate it");
}

@end
