//
//  GrowlDefines.h
//  Growl
//
//  Created by Karl Adam on Mon May 17 2004.
//  Copyright (c) 2004 __MyCompanyName__. All rights reserved.
//

#import <CoreFoundation/CoreFoundation.h>

/*!
    @header
    @abstract   Defines all the notification keys
    @discussion Defines all the keys used for registration and growl notifications.
*/

// UserInfo Keys for Registration
#pragma mark UserInfo Keys for Registration
/*! The name of your application */
#define GROWL_APP_NAME					@"ApplicationName"
/*! The TIFF data for the default icon for notifications (Optional) */
#define GROWL_APP_ICON					@"ApplicationIcon"
/*! The array of notifications to turn on by default */
#define GROWL_NOTIFICATIONS_DEFAULT		@"DefaultNotifications"
/*! The array of all notifications your application can send */
#define GROWL_NOTIFICATIONS_ALL			@"AllNotifications"
/*! The array of notifications the user has turned on */
#define GROWL_NOTIFICATIONS_USER_SET	@"AllowedUserNotifications"

// UserInfo Keys for Notifications
#pragma mark UserInfo Keys for Notifications
/*! The name of the notification. This should be human-readable as it's shown in the prefpane */
#define GROWL_NOTIFICATION_NAME			@"NotificationName"
/*! The title to display in the notification */
#define GROWL_NOTIFICATION_TITLE		@"NotificationTitle"
/*! The contents of the notification */
#define GROWL_NOTIFICATION_DESCRIPTION  @"NotificationDescription"
/*! The TIFF data for the notification icon (Optional) */
#define GROWL_NOTIFICATION_ICON			@"NotificationIcon"
/*! The TIFF data for the application icon (Optional) */
#define GROWL_NOTIFICATION_APP_ICON		@"NotificationAppIcon"
/*! The priority of the notification from the preference pane */
#define GROWL_NOTIFICATION_PRIORITY		@"NotificationPriority"
/*! A boolean controlling whether the notification is sticky. (Optional)
	
	Not necessarily supported by all display plugins */
#define GROWL_NOTIFICATION_STICKY		@"NotificationSticky"

// Notifications
#pragma mark Notifications
/*! The distributed notification name to use for registration */
#define GROWL_APP_REGISTRATION			@"GrowlApplicationRegistrationNotification"
/*! The distributed notification sent to confirm the registration. Used by the prefpane */
#define GROWL_APP_REGISTRATION_CONF		@"GrowlApplicationRegistrationConfirmationNotification"
/*! The distributed notification name to use for growl notifications */
#define GROWL_NOTIFICATION				@"GrowlNotification"
/*! The distributed notification name to use to tell Growl to shutdown (this is a guess) */
#define GROWL_SHUTDOWN					@"GrowlShutdown"
/*! The distribued notification sent to check if Growl is running. Used by the prefpane */
#define GROWL_PING						@"Honey, Mind Taking Out The Trash"
/*! The distributed notification sent in reply to GROWL_PING */
#define GROWL_PONG						@"What Do You Want From Me, Woman"

/*! The distributed notification sent when Growl starts up (this is a guess) */
#define GROWL_IS_READY					@"Lend Me Some Sugar; I Am Your Neighbor!"

/* --- These following macros are intended for plugins --- */

/*!
	@function    SYNCHRONIZE_GROWL_PREFS
	@abstract    Synchronizes Growl prefs so it's up-to-date
	@discussion  This macro is intended for use by GrowlHelperApp and by
	plugins (when the prefpane is selected).
 */
#define SYNCHRONIZE_GROWL_PREFS() CFPreferencesAppSynchronize(CFSTR("com.Growl.GrowlHelperApp"))

/*!
	@function    UPDATE_GROWL_PREFS
	@abstract    Tells GrowlHelperApp to update its prefs
	@discussion  This macro is intended for use by plugins.
	It sends a notification to tell GrowlHelperApp to update its preferences.
 */
#define UPDATE_GROWL_PREFS() do { SYNCHRONIZE_GROWL_PREFS(); \
	[[NSDistributedNotificationCenter defaultCenter] \
		postNotificationName:@"GrowlPreferencesChanged" object:@"GrowlUserDefaults"]; } while(0)

/*!
    @function    READ_GROWL_PREF_VALUE
    @abstract    Reads the given pref value from the plugin's preferences
    @discussion  This macro is intended for use by plugins. It reads the value for the
	given key from the plugin's preferences (which are stored in a dictionary inside of
	GrowlHelperApp's prefs).
	@param key The preference key to read the value of
	@param domain The bundle ID of the plugin
	@param type The type of the result expected
	@param result A pointer to an id. Set to the value if exists, left unchanged if not.
	
	If the value is set, you are responsible for releasing it
 */
#define READ_GROWL_PREF_VALUE(key, domain, type, result) do {\
	CFDictionaryRef prefs = (CFDictionaryRef)CFPreferencesCopyAppValue((CFStringRef)domain, \
																		CFSTR("com.Growl.GrowlHelperApp")); \
	*result = NULL; \
	if (prefs != NULL) {\
		if (CFDictionaryContainsKey(prefs, key)) {\
			*result = (type)CFDictionaryGetValue(prefs, key); \
			CFRetain(*result); \
		}\
		CFRelease(prefs); } } while(0)

/*!
	@function    WRITE_GROWL_PREF_VALUE
	@abstract    Writes the given pref value to the plugin's preferences
	@discussion  This macro is intended for use by plugins. It writes the given value
	to the plugin's preferences.
	@param key The preference key to write the value of
	@param value The value to write to the preferences. It should be a CoreFoundation type or
	toll-free bridged with one
	@param domain The bundle ID of the plugin
 */
#define WRITE_GROWL_PREF_VALUE(key, value, domain) do {\
	CFDictionaryRef staticPrefs = (CFDictionaryRef)CFPreferencesCopyAppValue((CFStringRef)domain, \
																			 CFSTR("com.Growl.GrowlHelperApp")); \
	CFMutableDictionaryRef prefs; \
	if (staticPrefs == NULL) {\
		prefs = CFDictionaryCreateMutable(NULL, 0, NULL, NULL); \
	} else {\
		prefs = CFDictionaryCreateMutableCopy(NULL, 0, staticPrefs); \
		CFRelease(staticPrefs); \
	}\
	CFDictionarySetValue(prefs, key, value); \
	CFPreferencesSetAppValue((CFStringRef)domain, prefs, CFSTR("com.growl.GrowlHelperApp")); \
	CFRelease(prefs); } while(0)

/*!
@function    READ_GROWL_PREF_BOOL
	@abstract    Reads the given boolean from the plugin's preferences
	@discussion  This is a wrapper around READ_GROWL_PREF_VALUE() intended for
	use with booleans.
	@param key The preference key to read the boolean from
	@param domain The bundle ID of the plugin
	@param result A pointer to a boolean. Leaves unchanged if the value doesn't exist
 */
#define READ_GROWL_PREF_BOOL(key, domain, result) do {\
	*result = NO; \
	CFBooleanRef boolValue = NULL; \
	READ_GROWL_PREF_VALUE(key, domain, CFBooleanRef, &boolValue); \
	if (boolValue != NULL) {\
		*result = CFBooleanGetValue(boolValue); \
		CFRelease(boolValue); \
	} } while(0)

/*!
	@function    WRITE_GROWL_PREF_BOOL
	@abstract    Writes the given boolean to the plugin's preferences
	@discussion  This is a wrapper around WRITE_GROWL_PREF_VALUE() intended for
	use with booleans.
	@param key The preference key to write the boolean for
	@param value The boolean value to write to the preferences
	@param domain The bundle ID of the plugin
 */
#define WRITE_GROWL_PREF_BOOL(key, value, domain) do {\
	CFBooleanRef boolValue; \
	if (value) {\
		boolValue = kCFBooleanTrue; \
	} else {\
		boolValue = kCFBooleanFalse; \
	}\
	WRITE_GROWL_PREF_VALUE(key, boolValue, domain); } while(0)

/*!
@function    READ_GROWL_PREF_INT
	@abstract    Reads the given integer from the plugin's preferences
	@discussion  This is a wrapper around READ_GROWL_PREF_VALUE() intended for
	use with integers.
	@param key The preference key to read the integer from
	@param domain The bundle ID of the plugin
	@param result A pointer to an integer. Leaves unchanged if the value doesn't exist
 */
#define READ_GROWL_PREF_INT(key, domain, result) do {\
	*result = 0; \
	CFNumberRef intValue = NULL; \
	READ_GROWL_PREF_VALUE(key, domain, CFNumberRef, &intValue); \
	if (intValue != NULL) {\
		CFNumberGetValue(intValue, kCFNumberIntType, result); \
		CFRelease(intValue); \
	} } while(0)

/*!
	@function    WRITE_GROWL_PREF_INT
	@abstract    Writes the given integer to the plugin's preferences
	@discussion  This is a wrapper around WRITE_GROWL_PREF_VALUE() intended for
	use with integers.
	@param key The preference key to write the integer for
	@param value The integer value to write to the preferences
	@param domain The bundle ID of the plugin
 */
#define WRITE_GROWL_PREF_INT(key, value, domain) do {\
	CFNumberRef intValue = CFNumberCreate(NULL, kCFNumberIntType, &value); \
	WRITE_GROWL_PREF_VALUE(key, intValue, domain); \
	CFRelease(intValue); } while(0)

/*!
@function    READ_GROWL_PREF_FLOAT
	@abstract    Reads the given float from the plugin's preferences
	@discussion  This is a wrapper around READ_GROWL_PREF_VALUE() intended for
	use with floats.
	@param key The preference key to read the float from
	@param domain The bundle ID of the plugin
	@param result A pointer to a float. Leaves unchanged if the value doesn't exist
 */
#define READ_GROWL_PREF_FLOAT(key, domain, result) do {\
	*result = 0.0; \
	CFNumberRef floatValue = NULL; \
	READ_GROWL_PREF_VALUE(key, domain, CFNumberRef, &floatValue); \
	if (floatValue != NULL) {\
		CFNumberGetValue(floatValue, kCFNumberFloatType, result); \
		CFRelease(floatValue); \
	} } while(0)

/*!
	@function    WRITE_GROWL_PREF_FLOAT
	@abstract    Writes the given float to the plugin's preferences
	@discussion  This is a wrapper around WRITE_GROWL_PREF_VALUE() intended for
	use with floats.
	@param key The preference key to write the float for
	@param value The float value to write to the preferences
	@param domain The bundle ID of the plugin
 */
#define WRITE_GROWL_PREF_FLOAT(key, value, domain) do {\
	CFNumberRef floatValue = CFNumberCreate(NULL, kCFNumberFloatType, &value); \
	WRITE_GROWL_PREF_VALUE(key, floatValue, domain); \
	CFRelease(floatValue); } while(0)
