#import <Foundation/Foundation.h>

static BOOL FSAudioMatches(NSString *value, NSString *pattern) {
    return [value rangeOfString:pattern options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound;
}

// Only explicit metadata establishes language/original status; default and order do not.
static NSInteger FSAudioPreferenceScore(NSString *language, NSString *label) {
    NSString *base=[[[language ?: @"" lowercaseString] stringByReplacingOccurrencesOfString:@"_" withString:@"-"] componentsSeparatedByString:@"-"].firstObject;
    NSString *name=label ?: @"";
    BOOL known=base.length && ![@[@"und",@"unk",@"zxx"] containsObject:base];
    NSInteger rank=([@[@"en",@"eng"] containsObject:base] || (!known && FSAudioMatches(name,@"(^|[^\\p{L}])(english|английский|английская|eng|en)([^\\p{L}]|$)"))) ? 200 :
        FSAudioMatches(name,@"(^|[^\\p{L}])(original|оригинал|оригинальная)([^\\p{L}]|$)") ? 100 : 0;
    return rank ? rank-(FSAudioMatches(name,@"commentary|комментар|audio description|тифло") ? 10 : 0) : 0;
}
