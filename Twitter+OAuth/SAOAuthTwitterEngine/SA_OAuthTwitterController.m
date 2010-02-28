//
//  SA_OAuthTwitterController.m
//
//  Created by Ben Gottlieb on 24 July 2009.
//  Copyright 2009 Stand Alone, Inc.
//
//  Some code and concepts taken from examples provided by 
//  Matt Gemmell, Chris Kimpton, and Isaiah Carew
//  See ReadMe for further attributions, copyrights and license info.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#import "SA_OAuthTwitterEngine.h"

#import "SA_OAuthTwitterController.h"

// Constants
static NSString* const kGGTwitterLoadingBackgroundImage = @"twitter_load.png";
static const NSInteger kPinEntryViewTag = 110;
static const NSInteger kPinTextEntryTag = 111;
static const CGFloat KEYBOARD_ANIMATION_DURATION = 0.3;
static const CGFloat PORTRAIT_KEYBOARD_HEIGHT = 216;
static const CGFloat LANDSCAPE_KEYBOARD_HEIGHT = 162;

@interface SA_OAuthTwitterController ()
@property (nonatomic, readonly) UIToolbar *pinCopyPromptBar;
@property (nonatomic, readwrite) UIInterfaceOrientation orientation;

- (id) initWithEngine: (SA_OAuthTwitterEngine *) engine andOrientation:(UIInterfaceOrientation)theOrientation;
//- (void) performInjection;
- (NSString *) locateAuthPinInWebView: (UIWebView *) webView;

- (void) showPinCopyPrompt;
- (void) gotPin: (NSString *) pin;

// Used for 2.2.1, where the user can't copy the PIN
- (UIView *) pinEntryView;
- (void) processPinEntry;
- (void) showPinEntryView;
- (void) hidePinEntryView;

@end


@interface DummyClassForProvidingSetDataDetectorTypesMethod
- (void) setDataDetectorTypes: (int) types;
- (void) setDetectsPhoneNumbers: (BOOL) detects;
@end

@interface NSString (TwitterOAuth)
- (BOOL) oauthtwitter_isNumeric;
@end

@implementation NSString (TwitterOAuth)
- (BOOL) oauthtwitter_isNumeric {
	const char				*raw = (const char *) [self UTF8String];
	
	for (int i = 0; i < strlen(raw); i++) {
		if (raw[i] < '0' || raw[i] > '9') return NO;
	}
	return YES;
}
@end


@implementation SA_OAuthTwitterController
@synthesize engine = _engine, delegate = _delegate, navigationBar = _navBar, orientation = _orientation;


- (void) dealloc {
	[_backgroundView release];
	
	[[NSNotificationCenter defaultCenter] removeObserver: self];
	_webView.delegate = nil;
	[_webView loadRequest: [NSURLRequest requestWithURL: [NSURL URLWithString: @""]]];
	[_webView release];
	
	self.view = nil;
	self.engine = nil;
	[super dealloc];
}

+ (SA_OAuthTwitterController *) controllerToEnterCredentialsWithTwitterEngine: (SA_OAuthTwitterEngine *) engine delegate: (id <SA_OAuthTwitterControllerDelegate>) delegate forOrientation: (UIInterfaceOrientation)theOrientation {
	if (![self credentialEntryRequiredWithTwitterEngine: engine]) return nil;			//not needed
	
	SA_OAuthTwitterController					*controller = [[[SA_OAuthTwitterController alloc] initWithEngine: engine andOrientation: theOrientation] autorelease];
	
	controller.delegate = delegate;
	return controller;
}

+ (SA_OAuthTwitterController *) controllerToEnterCredentialsWithTwitterEngine: (SA_OAuthTwitterEngine *) engine delegate: (id <SA_OAuthTwitterControllerDelegate>) delegate {
	return [SA_OAuthTwitterController controllerToEnterCredentialsWithTwitterEngine: engine delegate: delegate forOrientation: UIInterfaceOrientationPortrait];
}


+ (BOOL) credentialEntryRequiredWithTwitterEngine: (SA_OAuthTwitterEngine *) engine {
	return ![engine isAuthorized];
}


- (id) initWithEngine: (SA_OAuthTwitterEngine *) engine andOrientation:(UIInterfaceOrientation)theOrientation {
	if (self = [super init]) {
		self.engine = engine;
		if (!engine.OAuthSetup) [_engine requestRequestToken];
		self.orientation = theOrientation;
		_firstLoad = YES;
		
		if (UIInterfaceOrientationIsLandscape( self.orientation ) )
			_webView = [[UIWebView alloc] initWithFrame: CGRectMake(0, 32, 480, 288)];
		else
			_webView = [[UIWebView alloc] initWithFrame: CGRectMake(0, 44, 320, 416)];
		
		_webView.alpha = 0.0;
		_webView.delegate = self;
		_webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		if ([_webView respondsToSelector: @selector(setDetectsPhoneNumbers:)]) [(id) _webView setDetectsPhoneNumbers: NO];
		if ([_webView respondsToSelector: @selector(setDataDetectorTypes:)]) [(id) _webView setDataDetectorTypes: 0];
		
		NSURLRequest			*request = _engine.authorizeURLRequest;
		[_webView loadRequest: request];
    
		[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(pasteboardChanged:) name: UIPasteboardChangedNotification object: nil];
	}
	return self;
}

//=============================================================================================================================
#pragma mark Actions
- (void) denied {
	if ([_delegate respondsToSelector: @selector(OAuthTwitterControllerFailed:)]) [_delegate OAuthTwitterControllerFailed: self];
	[self performSelector: @selector(dismissModal) withObject: nil afterDelay: 1.0];
}

- (void) gotPin: (NSString *) pin {
	_engine.pin = pin;
	[_engine requestAccessToken];
  
  if([_engine username] == nil) {
    [self hidePinEntryView];
    [_engine clearAccessToken];
    [_engine requestRequestToken];
		[_webView loadRequest: _engine.authorizeURLRequest];
  } else {
    if ([_delegate respondsToSelector: @selector(OAuthTwitterController:authenticatedWithUsername:)]) {
      [_delegate OAuthTwitterController: self authenticatedWithUsername: _engine.username];
    }
    [self performSelector: @selector(dismissModal) withObject: nil afterDelay: 1.0];
  }
}

- (void) cancel: (id) sender {
	if ([_delegate respondsToSelector: @selector(OAuthTwitterControllerCanceled:)]) [_delegate OAuthTwitterControllerCanceled: self];
	[self performSelector: @selector(dismissModal) withObject: nil afterDelay: 0.0];
}

//=============================================================================================================================
#pragma mark View Controller Stuff
- (void) dismissModal {
  [self dismissModalViewControllerAnimated:YES];
}

- (void) loadView {
	[super loadView];
  
	_backgroundView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:kGGTwitterLoadingBackgroundImage]];
	if ( UIInterfaceOrientationIsLandscape( self.orientation ) ) {
		self.view = [[[UIView alloc] initWithFrame: CGRectMake(0, 0, 480, 288)] autorelease];	
		_backgroundView.frame =  CGRectMake(0, 0, 480, 288);
		
		_navBar = [[[UINavigationBar alloc] initWithFrame: CGRectMake(0, 0, 480, 32)] autorelease];
	} else {
		self.view = [[[UIView alloc] initWithFrame: CGRectMake(0, 0, 320, 416)] autorelease];	
		_backgroundView.frame =  CGRectMake(0, 0, 320, 416);
		_navBar = [[[UINavigationBar alloc] initWithFrame: CGRectMake(0, 0, 320, 44)] autorelease];
	}
	_navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
	_backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  
	if (!UIInterfaceOrientationIsLandscape( self.orientation)) [self.view addSubview:_backgroundView];
	
	[self.view addSubview: _webView];
	[self.view addSubview: _navBar];
	
	_blockerView = [[[UIView alloc] initWithFrame: CGRectMake(0, 0, 200, 60)] autorelease];
	_blockerView.backgroundColor = [UIColor colorWithWhite: 0.0 alpha: 0.8];
	_blockerView.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
	_blockerView.alpha = 0.0;
	_blockerView.clipsToBounds = YES;
	if ([_blockerView.layer respondsToSelector: @selector(setCornerRadius:)]) [(id) _blockerView.layer setCornerRadius: 10];
	
	UILabel								*label = [[[UILabel alloc] initWithFrame: CGRectMake(0, 5, _blockerView.bounds.size.width, 15)] autorelease];
	label.text = NSLocalizedString(@"TWITTER_WAIT_REQUEST", nil);
	label.backgroundColor = [UIColor clearColor];
	label.textColor = [UIColor whiteColor];
	label.textAlignment = UITextAlignmentCenter;
	label.font = [UIFont boldSystemFontOfSize: 15];
	[_blockerView addSubview: label];
	
	UIActivityIndicatorView				*spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhite] autorelease];
	
	spinner.center = CGPointMake(_blockerView.bounds.size.width / 2, _blockerView.bounds.size.height / 2 + 10);
	[_blockerView addSubview: spinner];
	[self.view addSubview: _blockerView];
	[spinner startAnimating];
	
	UINavigationItem				*navItem = [[[UINavigationItem alloc] initWithTitle: NSLocalizedString(@"TWITTER_PAGE_TITLE", nil)] autorelease];
	navItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemCancel target: self action: @selector(cancel:)] autorelease];
	
	[_navBar pushNavigationItem: navItem animated: NO];
	[self locateAuthPinInWebView: nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  return YES;
}

- (void) didRotateFromInterfaceOrientation: (UIInterfaceOrientation) fromInterfaceOrientation {
	self.orientation = self.interfaceOrientation;
	_blockerView.center = CGPointMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2);
  //	[self performInjection];			//removed due to twitter update
}

//=============================================================================================================================
#pragma mark Notifications
- (void) pasteboardChanged: (NSNotification *) note {
	UIPasteboard					*pb = [UIPasteboard generalPasteboard];
	
	if ([note.userInfo objectForKey: UIPasteboardChangedTypesAddedKey] == nil) return;		//no meaningful change
	
	NSString						*copied = pb.string;
	
	if (copied.length < 6 || copied.length > 10 || !copied.oauthtwitter_isNumeric) return;
	
	[self gotPin: copied];
}


//=============================================================================================================================
#pragma mark PIN Entry for 2.2.1
- (UIView *) pinEntryView {
  // Create a new PIN entry view
  UIView *pinEntryView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 40)] autorelease];
  [pinEntryView setBackgroundColor:[UIColor blackColor]];
  [pinEntryView setTag:kPinEntryViewTag];
  
  UILabel *helpText = [[[UILabel alloc] initWithFrame:CGRectMake(10, 10, 165, 20)] autorelease];
  [helpText setText:NSLocalizedString(@"ENTER_PIN_INSTRUCTIONS", nil)];
  [helpText setBackgroundColor:[UIColor clearColor]];
  [helpText setTextColor:[UIColor whiteColor]];
  [helpText setFont:[UIFont systemFontOfSize:13]];
  [pinEntryView addSubview:helpText];
  
  UITextField *pinEntryField = [[[UITextField alloc] initWithFrame:CGRectMake(160, 7, 70, 24)] autorelease];
  [pinEntryField setBorderStyle:UITextBorderStyleBezel];
  [pinEntryField setBackgroundColor:[UIColor whiteColor]];
  [pinEntryField setTag:kPinTextEntryTag];
  [pinEntryField setKeyboardType:UIKeyboardTypeNumberPad];
  [pinEntryField setFont:[UIFont systemFontOfSize:13]];
  [pinEntryField setDelegate:self];
  [pinEntryView addSubview:pinEntryField];
  
  UIButton *submitButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
  [submitButton setTitle:NSLocalizedString(@"PIN_DONE_BUTTON", nil) forState:UIControlStateNormal];
  if([submitButton respondsToSelector:@selector(titleLabel)]) {
    submitButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
  } else {
    [submitButton performSelector:@selector(setFont:) withObject:[UIFont boldSystemFontOfSize:16]];
  }
  [submitButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
  [submitButton setFrame:CGRectMake(240, 7, 70, 24)];
  [submitButton addTarget:self action:@selector(processPinEntry) forControlEvents:UIControlEventTouchUpInside];
  [pinEntryView addSubview:submitButton];
	
	return pinEntryView;
}

- (void) processPinEntry {
	UITextField *pinField = (UITextField *)[[self view] viewWithTag:kPinTextEntryTag];
  NSString *pinText = [pinField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

	if(pinText.length == 7) {
    [pinField resignFirstResponder];
    
		[self gotPin:pinText];
	}
}

- (void) showPinEntryView {
  UIView *pinEntryView = [self.view viewWithTag:kPinEntryViewTag];
  
  if(pinEntryView == nil) {
    pinEntryView = [self pinEntryView];
  	[[self view] addSubview:pinEntryView];    
  
    // Clear the PIN entry box
    UITextField *pinEntryField = (UITextField *)[pinEntryView viewWithTag:kPinTextEntryTag];
    pinEntryField.text = @"";
    
    [UIView beginAnimations:nil context:NULL]; {
      // Reduce the size of the WebView
      CGRect webFrame = _webView.frame;
      CGFloat pinHeight = pinEntryView.frame.size.height;
      webFrame.origin.y += pinHeight;
      webFrame.size.height -= pinHeight;
      _webView.frame = webFrame;
      
      // Place the PIN entry view at the top
      pinEntryView.frame = CGRectMake(0, 44, 320, 40);
    } [UIView commitAnimations];
  }
}

- (void) hidePinEntryView {
  UIView *pinEntryView = [self.view viewWithTag:kPinEntryViewTag];
  
  if(pinEntryView != nil) {
    [UIView beginAnimations:nil context:NULL]; {
      // Restore the size of the WebView
      CGRect webFrame = _webView.frame;
      CGFloat pinHeight = pinEntryView.frame.size.height;
      webFrame.origin.y -= pinHeight;
      webFrame.size.height += pinHeight;
      _webView.frame = webFrame;
      
      pinEntryView.frame = CGRectMake(0, 0, 320, 40);
      [pinEntryView removeFromSuperview];
    } [UIView commitAnimations];
  }
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
  if(textField.tag == kPinTextEntryTag) {
    UIInterfaceOrientation orientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortraitUpsideDown) {
      animatedDistance = PORTRAIT_KEYBOARD_HEIGHT;
    } else {
      animatedDistance = LANDSCAPE_KEYBOARD_HEIGHT;
    }
    
    CGRect webFrame = _webView.frame;
    webFrame.origin.y -= animatedDistance;
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationDuration:KEYBOARD_ANIMATION_DURATION];
    
    [_webView setFrame:webFrame];
    
    [UIView commitAnimations];
  }
}

- (void) textFieldDidEndEditing:(UITextField *) textField {
  if(textField.tag == kPinTextEntryTag) {
    CGRect webFrame = _webView.frame;
    webFrame.origin.y += animatedDistance;
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [UIView setAnimationDuration:KEYBOARD_ANIMATION_DURATION];
    [_webView setFrame:webFrame];
    [UIView commitAnimations];
  }
}

//=============================================================================================================================
#pragma mark Webview Delegate stuff
- (void) webViewDidFinishLoad: (UIWebView *) webView {
	_loading = NO;
  
	if (_firstLoad) {
		[_webView performSelector: @selector(stringByEvaluatingJavaScriptFromString:) withObject: @"window.scrollBy(0,200)" afterDelay: 0];
		_firstLoad = NO;
	} else {
    // Check the user got their username & password right
    NSString *invalidLocationString = [webView stringByEvaluatingJavaScriptFromString: @"document.body.innerHTML.indexOf('Invalid');"];
    if([invalidLocationString intValue] == -1) {
      // Attempt to find the PIN using JavaScript
      NSString *authPin = [self locateAuthPinInWebView: webView];
      
      if (authPin != nil) {
        [self gotPin: authPin];
        return;
      }
      
      // If we can't find the PIN ourselves, ask the user to copy it to clipboard (OS >= 3.0)
      if(NSClassFromString(@"UIPasteboard") != nil) {
        NSString *formCount = [webView stringByEvaluatingJavaScriptFromString: @"document.forms.length"];
      
        if ([formCount isEqualToString: @"0"]) {
          [self showPinCopyPrompt];
        }
      } else {
        // Show controls for PIN entry in 2.2.1 - but first, check if we got here
        // due to an incorrect PIN
        NSString *pinLocationString = [webView stringByEvaluatingJavaScriptFromString: @"document.body.innerHTML.indexOf('PIN');"];
        if([pinLocationString intValue] > -1) {
          [self showPinEntryView];
        }
      }
    }
	}
	
  // Fade out the loading view
	[UIView beginAnimations: nil context: nil];
	_blockerView.alpha = 0.0;
	[UIView commitAnimations];
	
	if ([_webView isLoading]) {
		_webView.alpha = 0.0;
	} else {
		_webView.alpha = 1.0;
	}
}

- (void) showPinCopyPrompt {
	if (self.pinCopyPromptBar.superview) return;		//already shown
	self.pinCopyPromptBar.center = CGPointMake(self.pinCopyPromptBar.bounds.size.width / 2, self.pinCopyPromptBar.bounds.size.height / 2);
	[self.view insertSubview: self.pinCopyPromptBar belowSubview: self.navigationBar];
	
	[UIView beginAnimations: nil context: nil];
	self.pinCopyPromptBar.center = CGPointMake(self.pinCopyPromptBar.bounds.size.width / 2, self.navigationBar.bounds.size.height + self.pinCopyPromptBar.bounds.size.height / 2);
	[UIView commitAnimations];
}

- (NSString *) locateAuthPinInWebView: (UIWebView *) webView {
  // Look for either 'oauth-pin' or 'oauth_pin' in the raw HTML
	NSString			*js = @"var d = document.getElementById('oauth-pin'); if (d == null) d = document.getElementById('oauth_pin'); if (d) d = d.innerHTML; d;";
	NSString			*pin = [[webView stringByEvaluatingJavaScriptFromString: js] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (pin.length == 7) {
    return pin;
  }
	
	return nil;
}

- (UIToolbar *) pinCopyPromptBar {
	if (_pinCopyPromptBar == nil){
		CGRect					bounds = self.view.bounds;
		
		_pinCopyPromptBar = [[[UIToolbar alloc] initWithFrame:CGRectMake(0, 44, bounds.size.width, 44)] autorelease];
		_pinCopyPromptBar.barStyle = UIBarStyleBlackTranslucent;
		_pinCopyPromptBar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    
		_pinCopyPromptBar.items = [NSArray arrayWithObjects: 
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target: nil action: nil] autorelease],
                               [[[UIBarButtonItem alloc] initWithTitle: NSLocalizedString(@"PIN_COPY_BAR_INSTRUCTIONS", nil) style: UIBarButtonItemStylePlain target: nil action: nil] autorelease], 
                               [[[UIBarButtonItem alloc] initWithBarButtonSystemItem: UIBarButtonSystemItemFlexibleSpace target: nil action: nil] autorelease], 
                               nil];
	}
	
	return _pinCopyPromptBar;
}


- (void) webViewDidStartLoad: (UIWebView *) webView {
	_loading = YES;
	[UIView beginAnimations: nil context: nil];
	_blockerView.alpha = 1.0;
	[UIView commitAnimations];
}


- (BOOL) webView: (UIWebView *) webView shouldStartLoadWithRequest: (NSURLRequest *) request navigationType: (UIWebViewNavigationType) navigationType {
	NSData				*data = [request HTTPBody];
	char				*raw = data ? (char *) [data bytes] : "";
	
	if (raw && strstr(raw, "cancel=")) {
		[self denied];
		return NO;
	}
	if (navigationType != UIWebViewNavigationTypeOther) _webView.alpha = 0.1;
	return YES;
}

@end
