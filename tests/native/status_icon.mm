#import "../../macos/Native/FSStatusIcon.h"
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#include <cassert>
#include <vector>

int main(int argc, const char **argv) {
    @autoreleasepool {
        int checks=0;
        for (int size : {18,36,180}) {
            std::vector<unsigned char> pixels(size*size*4,0);
            CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            CGContextRef c=CGBitmapContextCreate(pixels.data(),size,size,8,size*4,space,kCGImageAlphaPremultipliedLast);
            FSDrawStatusTemplate(c,CGRectMake(0,0,size,size));
            int transparent=0,visible=0; unsigned long alphaSum=0;
            for(int i=0;i<size*size;++i) {
                assert(pixels[i*4]==0 && pixels[i*4+1]==0 && pixels[i*4+2]==0);
                if(pixels[i*4+3]==0)++transparent; else ++visible;
                alphaSum+=pixels[i*4+3];
            }
            assert(transparent>size*size/5 && alphaSum<255UL*size*size/2); ++checks;
            assert(visible>size*size/8); ++checks;
            assert(pixels[3]==0); ++checks;
            assert(pixels[((9*size/18)*size+15*size/18)*4+3]==0); ++checks;
            if(size==180 && argc>1) {
                CGImageRef image=CGBitmapContextCreateImage(c);
                NSURL *url=[NSURL fileURLWithPath:@(argv[1])];
                CGImageDestinationRef output=CGImageDestinationCreateWithURL((__bridge CFURLRef)url,CFSTR("public.png"),1,nullptr);
                CGImageDestinationAddImage(output,image,nullptr); assert(CGImageDestinationFinalize(output));
                CFRelease(output);CGImageRelease(image);
                if(argc>2) {
                    CGContextRef preview=CGBitmapContextCreate(nullptr,360,180,8,0,space,kCGImageAlphaPremultipliedLast);
                    CGContextSetRGBFillColor(preview,0.96,0.95,0.94,1);CGContextFillRect(preview,CGRectMake(0,0,180,180));
                    CGContextSetRGBFillColor(preview,0.08,0.10,0.13,1);CGContextFillRect(preview,CGRectMake(180,0,180,180));
                    CGImageRef mask=CGBitmapContextCreateImage(c);
                    for(int x : {0,180}) {
                        CGContextSaveGState(preview);CGContextClipToMask(preview,CGRectMake(x+20,20,140,140),mask);
                        CGFloat color=x?1:0;CGContextSetRGBFillColor(preview,color,color,color,1);CGContextFillRect(preview,CGRectMake(x,0,180,180));CGContextRestoreGState(preview);
                    }
                    NSURL *qa=[NSURL fileURLWithPath:@(argv[2])];
                    CGImageDestinationRef file=CGImageDestinationCreateWithURL((__bridge CFURLRef)qa,CFSTR("public.png"),1,nullptr);
                    CGImageRef rendered=CGBitmapContextCreateImage(preview);CGImageDestinationAddImage(file,rendered,nullptr);assert(CGImageDestinationFinalize(file));
                    CFRelease(file);CGImageRelease(rendered);CGImageRelease(mask);CGContextRelease(preview);
                }
            }
            CGContextRelease(c);CGColorSpaceRelease(space);
        }
        printf("{\"passed\":true,\"checks\":%d,\"scales\":[1,2,10],\"transparentInterior\":true}\n",checks);
    }
}
