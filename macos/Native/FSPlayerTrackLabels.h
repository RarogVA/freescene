#import <Foundation/Foundation.h>

static inline NSString *FSNumberedTrack(NSInteger number, BOOL english) {
    return [NSString stringWithFormat:english ? @"Track %ld" : @"Дорожка %ld", (long)number];
}

static inline NSString *FSLocalizedTrackName(NSString *code, NSString *label, BOOL english) {
    NSString *name = [label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if (!code.length || [code.lowercaseString isEqual:@"und"]) return name;
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:english ? @"en" : @"ru"];
    NSString *language = [locale localizedStringForLanguageCode:code];
    if (!language.length) return name;
    NSLocale *otherLocale = [NSLocale localeWithLocaleIdentifier:english ? @"ru" : @"en"];
    NSString *otherName = [otherLocale localizedStringForLanguageCode:code];
    if (!name.length || [name caseInsensitiveCompare:language] == NSOrderedSame ||
        [name caseInsensitiveCompare:code] == NSOrderedSame ||
        (otherName && [name caseInsensitiveCompare:otherName] == NSOrderedSame)) {
        return [language capitalizedStringWithLocale:locale];
    }
    return [NSString stringWithFormat:@"%@ · %@", [language capitalizedStringWithLocale:locale], name];
}
