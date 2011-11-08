//
//  CIMInputController.m
//  CharmIM
//
//  Created by youknowone on 11. 8. 31..
//  Copyright 2011 youknowone.org. All rights reserved.
//

#import <AppKit/AppKit.h>

#import "CIMCommon.h"
#import "CIMApplicationDelegate.h"

#import "CIMInputManager.h"
#import "CIMComposer.h"

#import "CIMInputController.h"
#import "CIMConfiguration.h"

#define DEBUG_INPUTCONTROLLER TRUE

#define CIMSharedInputManager CIMAppDelegate.sharedInputManager

@implementation CIMInputController

- (id)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)inputClient {
    self = [super initWithServer:server delegate:delegate client:inputClient];
    if (self != nil) {
        ICLog(DEBUG_INPUTCONTROLLER, @"**** NEW INPUT CONTROLLER INIT **** WITH SERVER: %@ / DELEGATE: %@ / CLIENT: %@", server, delegate, inputClient);
        if (!CIMSharedInputManager.configuration->sharedInputManager) {
            self->composer = [[CIMAppDelegate composerWithServer:server client:inputClient] retain];
        }
    }
    return self;
}

- (CIMComposer *)composer {
    return self->composer ? self->composer : CIMSharedInputManager.sharedComposer;
}

#pragma - CIMInputControllerDelegate

enum {
    KeyCodeLeftArrow = 123,
    KeyCodeRightArrow = 124,
    KeyCodeDownArrow = 125,
    KeyCodeUpArrow = 126
};

// IMKServerInput 프로토콜에 대한 공용 핸들러
- (BOOL)inputController:(CIMInputController *)controller inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)flags client:(id)sender {
    // 화살표 키가 입력으로 들어오면 강제 커밋
    if (KeyCodeLeftArrow <= keyCode && keyCode <= KeyCodeUpArrow) {
        [self commitComposition:sender];
        ICLog(DEBUG_INPUTCONTROLLER, @"!! Commit composition on arrow keys");
        return NO;
    }
    
    BOOL handled = [CIMSharedInputManager inputController:controller inputText:string key:keyCode modifiers:flags client:sender];
    if (!handled) {
        // 한글 입력기가 처리하지 않는 문자는 한글 조합을 종료
        [self cancelComposition];
    }
    
    CIMSharedInputManager.inputting = YES;
    [self commitComposition:sender]; // 조합 된 문자 반영
    [self updateComposition]; // 조합 중인 문자 반영 
    CIMSharedInputManager.inputting = NO;
    ICLog(DEBUG_INPUTCONTROLLER, @"*** End of Input handling ***");
    return handled; 
}

@end

#pragma - IMKServerInput Protocol

// IMKServerInputTextData, IMKServerInputHandleEvent, IMKServerInputKeyBinding 중 하나를 구현하여 입력 구현

@implementation CIMInputController (IMKServerInputTextData)

- (BOOL)inputText:(NSString *)string key:(NSInteger)keyCode modifiers:(NSUInteger)flags client:(id)sender
{
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -inputText:key:modifiers:client  with string: %@ / keyCode: %d / modifier flags: %u / client: %@(%@)", string, keyCode, flags, [[self client] bundleIdentifier], [[self client] class]);
    
    return [self inputController:self inputText:string key:keyCode modifiers:flags client:sender];
}

@end

/*
@implementation CIMInputController (IMKServerInputHandleEvent)

// Receiving Events Directly from the Text Services Manager
- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if ([event type] != NSKeyDown) {
        ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -handleEvent:client: with event: %@ / sender: %@", event, sender);
        return NO;
    }
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -handleEvent:client: with event: %@ / key: %d / modifier: %d / chars: %@ / chars ignoreMod: %@ / client: %@", event, [event keyCode], [event modifierFlags], [event characters], [event charactersIgnoringModifiers], [[self client] bundleIdentifier]);
    return [self inputController:self inputText:[event characters] key:[event keyCode] modifiers:[event modifierFlags] client:sender];
}

@end
*/
/*
@implementation CIMInputController (IMKServerInputKeyBinding)

- (BOOL)inputText:(NSString *)string client:(id)sender {
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -inputText:client: with string: %@ / client: %@", string, sender);
    return NO;
}

- (BOOL)didCommandBySelector:(SEL)aSelector client:(id)sender {
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -didCommandBySelector: with selector: %@", aSelector);
    
    return NO;
}

@end
*/

@implementation CIMInputController (IMKServerInput)

// Committing a Composition
// 조합을 중단하고 현재까지 조합된 글자를 커밋한다.
- (void)commitComposition:(id)sender {
    if (!CIMSharedInputManager.inputting) {
        // 외부에서 들어오는 커밋 요청에 대해서는 편집 중인 글자도 커밋한다.
        ICLog(DEBUG_INPUTCONTROLLER, @"-- CANCEL composition because of external commit request from %@", sender);
        [self cancelComposition];
    }
    // 왠지는 모르겠지만 프로그램마다 동작이 달라서 조합을 반드시 마쳐주어야 한다
    // 터미널과 같이 조합중에 리턴키 먹는 프로그램은 조합 중인 문자가 없고 보통은 있다
    NSString *commitString = [self.composer dequeueCommitString];
    if ([commitString length] == 0) return; // 커밋할 문자가 없으면 중단
    
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -commitComposition: with sender: %@ / strings: %@", sender, commitString);
    [sender insertText:commitString replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
}

#if IC_DEBUG
- (void)updateComposition {
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -updateComposition");
    [super updateComposition];
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -updateComposition ended");
}
#endif

- (void)cancelComposition {
    [self.composer cancelComposition];
    [super cancelComposition];
}

// Getting Input Strings and Candidates
// 현재 입력 중인 글자를 반환한다. -updateComposition: 이 사용
- (id)composedString:(id)sender {
    NSString *string = self.composer.composedString;
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -composedString: with sender: %@ / return: %@", sender, string);
    return string;
}

- (NSAttributedString *)originalString:(id)sender {
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -originalString: with sender: %@", sender);
    return [[[NSAttributedString alloc] initWithString:[self.composer originalString]] autorelease];
}
@end

@implementation CIMInputController (IMKStateSetting)

//! @brief  마우스 이벤트를 잡을 수 있게 한다.
- (NSUInteger)recognizedEvents:(id)sender
{
    // NSFlagsChangeMask는 -handleEvent: 에서만 동작
    return NSKeyDownMask | NSFlagsChangedMask | NSLeftMouseDownMask | NSRightMouseDownMask | NSLeftMouseDraggedMask | NSRightMouseDraggedMask;
}

//! @brief 자판 전환을 감지한다.
- (void)setValue:(id)value forTag:(long)tag client:(id)sender {
    ICLog(DEBUG_INPUTCONTROLLER, @"** CIMInputController -setValue:forTag:client: with value: %@ / tag: %x / sender: %@ / client: %@", value, tag, sender, self.client);
    switch (tag) {
        case kTextServiceInputModePropertyTag:
            if (![value isEqualToString:self.composer.inputMode]) {
                ICAssert(sender != nil);
                [self commitComposition:sender];
                self.composer.inputMode = value;
            }
            break;
        default:
            ICLog(DEBUG_INPUTCONTROLLER, @"**** UNKNOWN TAG %d !!! ****", tag);
            break;
    }
}

@end

@implementation CIMInputController (IMKMouseHandling)

/*!
    @brief  마우스 입력 발생을 커서 옮기기로 간주하고 조합 중지. 만일 마우스 입력 발생을 감지하는 대신 커서 옮기기를 직접 알아낼 수 있으면 이 부분은 제거한다.
*/
- (BOOL)mouseDownOnCharacterIndex:(NSUInteger)index coordinate:(NSPoint)point withModifier:(NSUInteger)flags continueTracking:(BOOL *)keepTracking client:(id)sender
{
    [self commitComposition:sender];
    return NO;
}

@end

@implementation CIMInputController (IMKCustomCommands)

- (NSMenu *)menu {
    return [CIMAppDelegate menu];
}

@end
