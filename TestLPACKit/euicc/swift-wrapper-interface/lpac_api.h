#pragma once

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

// Error codes
typedef enum
{
    LPAC_SUCCESS = 0,
    LPAC_ERROR_GENERAL = -1,
    LPAC_ERROR_MEMORY = -2,
    LPAC_ERROR_INVALID_PARAMETER = -3,
    LPAC_ERROR_COMMUNICATION = -4,
    LPAC_ERROR_AUTHENTICATION = -5,
    LPAC_ERROR_PROFILE = -6
} lpac_error_t;

// Forward declarations
struct lpac_context;
typedef struct lpac_context *lpac_context_t;

// Profile information structure
typedef struct
{
    char *iccid;
    char *name;
    char *provider;
    char *nickname;
    char *isdp_aid;
    int state;         // 0 = disabled, 1 = enabled
    int profile_class; // 0 = unknown, 1 = test, 2 = provisioning, 3 = operational
} lpac_profile_info_t;

// Profile list structure
typedef struct
{
    lpac_profile_info_t *profiles;
    int count;
} lpac_profile_list_t;

// Notification structure
typedef struct
{
    uint64_t seq_number;
    char *notification_address;
    char *iccid;
    int operation; // 0 = unknown, 1 = install, 2 = delete, 3 = enable, 4 = disable
} lpac_notification_t;

// Notification list structure
typedef struct
{
    lpac_notification_t *notifications;
    int count;
} lpac_notification_list_t;

// Download states
typedef enum
{
    LPAC_DOWNLOAD_STATE_PREPARING = 0,
    LPAC_DOWNLOAD_STATE_CONNECTING = 1,
    LPAC_DOWNLOAD_STATE_AUTHENTICATING = 2,
    LPAC_DOWNLOAD_STATE_DOWNLOADING = 3,
    LPAC_DOWNLOAD_STATE_FINALIZING = 4
} lpac_download_state_t;

// Callback for download progress
typedef void (*lpac_download_callback_t)(lpac_download_state_t state, void *user_data);

// APDU interface callbacks
typedef struct
{
    int (*connect)(void *user_data);
    void (*disconnect)(void *user_data);
    int (*logical_channel_open)(const uint8_t *aid, uint8_t aid_len, void *user_data);
    void (*logical_channel_close)(uint8_t channel, void *user_data);
    int (*transmit)(uint8_t **rx, uint32_t *rx_len, const uint8_t *tx, uint32_t tx_len, void *user_data);
} lpac_apdu_interface_t;

// HTTP interface callbacks
typedef struct
{
    int (*transmit)(const char *url, uint32_t *rcode, uint8_t **rx, uint32_t *rx_len,
                    const uint8_t *tx, uint32_t tx_len, const char **headers, void *user_data);
} lpac_http_interface_t;

// Context creation and destruction
lpac_context_t lpac_create_context(const uint8_t *isdr_aid, uint32_t isdr_len,
                                   lpac_apdu_interface_t *apdu_interface,
                                   lpac_http_interface_t *http_interface,
                                   void *user_data);
void lpac_destroy_context(lpac_context_t ctx);

// Initialization
lpac_error_t lpac_init(lpac_context_t ctx);
void lpac_fini(lpac_context_t ctx);
void lpac_set_mss(lpac_context_t ctx, uint8_t mss);

// EID operations
lpac_error_t lpac_get_eid(lpac_context_t ctx, char **eid);

// Profile operations
lpac_error_t lpac_get_profiles_info(lpac_context_t ctx, lpac_profile_list_t **profiles);
void lpac_free_profile_list(lpac_profile_list_t *profiles);
lpac_error_t lpac_enable_profile(lpac_context_t ctx, const char *iccid, bool refresh);
lpac_error_t lpac_disable_profile(lpac_context_t ctx, const char *iccid, bool refresh);
lpac_error_t lpac_delete_profile(lpac_context_t ctx, const char *iccid);
lpac_error_t lpac_set_nickname(lpac_context_t ctx, const char *iccid, const char *nickname);

// Profile download
lpac_error_t lpac_download_profile(lpac_context_t ctx,
                                   const char *smdp,
                                   const char *matching_id,
                                   const char *imei,
                                   const char *confirmation_code,
                                   lpac_download_callback_t callback,
                                   void *user_data);
void lpac_cancel_sessions(lpac_context_t ctx);
const char *lpac_download_error_to_string(int error_code);

// Notification handling
lpac_error_t lpac_list_notifications(lpac_context_t ctx, lpac_notification_list_t **notifications);
void lpac_free_notification_list(lpac_notification_list_t *notifications);
lpac_error_t lpac_handle_notification(lpac_context_t ctx, uint64_t seq_number);
lpac_error_t lpac_delete_notification(lpac_context_t ctx, uint64_t seq_number);

// Memory operations
void lpac_free_string(char *str);
// Device information
typedef struct
{
    char *profileVersion;
    char *svn;
    char *euiccFirmwareVer;
    uint32_t installedApplication;
    uint32_t freeNonVolatileMemory;
    uint32_t freeVolatileMemory;
    char **uiccCapability;
    char *ts102241Version;
    char *globalplatformVersion;
    char **rspCapability;
    char **euiccCiPKIdListForVerification;
    char **euiccCiPKIdListForSigning;
    char *euiccCategory;
    char **forbiddenProfilePolicyRules;
    char *ppVersion;
    char *sasAcreditationNumber;
    struct
    {
        char *platformLabel;
        char *discoveryBaseURL;
    } certificationDataObject;
} lpac_euicc_info2;

lpac_error_t lpac_get_euicc_info(lpac_context_t ctx,lpac_euicc_info2 **info);
void lpac_free_euicc_info(lpac_euicc_info2 *info);

// Memory reset
lpac_error_t lpac_memory_reset(lpac_context_t ctx);

#ifdef __cplusplus
}
#endif
