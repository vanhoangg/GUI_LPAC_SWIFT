//
//  TestLPACKit-Bridging-Header.h
//  TestLPACKit
//

#ifndef TestLPACKit_Bridging_Header_h
#define TestLPACKit_Bridging_Header_h

// Import all header files from euicc folder
#import <Foundation/Foundation.h>
#include "lpac_api.h"
// Swift-friendly enums
typedef NS_ENUM(NSInteger, LpacError) {
    LpacErrorSuccess = LPAC_SUCCESS,
    LpacErrorGeneral = LPAC_ERROR_GENERAL,
    LpacErrorMemory = LPAC_ERROR_MEMORY,
    LpacErrorInvalidParameter = LPAC_ERROR_INVALID_PARAMETER,
    LpacErrorCommunication = LPAC_ERROR_COMMUNICATION,
    LpacErrorAuthentication = LPAC_ERROR_AUTHENTICATION,
    LpacErrorProfile = LPAC_ERROR_PROFILE
};

typedef NS_ENUM(NSInteger, LpacDownloadState) {
    LpacDownloadStatePreparing = LPAC_DOWNLOAD_STATE_PREPARING,
    LpacDownloadStateConnecting = LPAC_DOWNLOAD_STATE_CONNECTING,
    LpacDownloadStateAuthenticating = LPAC_DOWNLOAD_STATE_AUTHENTICATING,
    LpacDownloadStateDownloading = LPAC_DOWNLOAD_STATE_DOWNLOADING,
    LpacDownloadStateFinalizing = LPAC_DOWNLOAD_STATE_FINALIZING

};

typedef NS_ENUM(NSInteger, LpacProfileState) {
    LpacProfileStateDisabled = 0,
    LpacProfileStateEnabled = 1
};

typedef NS_ENUM(NSInteger, LpacProfileClass) {
    LpacProfileClassUnknown = 0,
    LpacProfileClassTest = 1,
    LpacProfileClassProvisioning = 2,
    LpacProfileClassOperational = 3
};



#endif /* TestLPACKit_Bridging_Header_h */





