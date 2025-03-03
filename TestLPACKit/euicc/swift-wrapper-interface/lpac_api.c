#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include "euicc.h"
#include "es10c.h"
#include "es10c_ex.h"
#include "es9p.h"
#include "es10b.h"
#include "interface.h"
#include "lpac_api.h"


// Internal context structure
struct lpac_context
{
    struct euicc_ctx euicc_ctx;           // euicc context
    lpac_apdu_interface_t apdu_interface; // APDU callbacks
    lpac_http_interface_t http_interface; // HTTP callbacks
    void *user_data;                      // User data passed to callbacks
    uint8_t *aid;                         // Copy of AID
    uint32_t aid_len;                     // Length of AID
    int logical_channel_id;               // Current logical channel ID
};

// Internal download callback data
typedef struct
{
    lpac_download_callback_t callback;
    void *user_data;
} download_callback_data_t;

// APDU interface implementation
static int apdu_interface_connect(struct euicc_ctx *ctx)
{
    lpac_context_t lpac_ctx = (lpac_context_t)ctx->userdata;
    if (lpac_ctx->apdu_interface.connect)
    {
        return lpac_ctx->apdu_interface.connect(lpac_ctx->user_data);
    }
    return 0;
}

static void apdu_interface_disconnect(struct euicc_ctx *ctx)
{
    lpac_context_t lpac_ctx = (lpac_context_t)ctx->userdata;
    if (lpac_ctx->apdu_interface.disconnect)
    {
        lpac_ctx->apdu_interface.disconnect(lpac_ctx->user_data);
    }
}

static int apdu_interface_logical_channel_open(struct euicc_ctx *ctx, const uint8_t *aid, uint8_t aid_len)
{
    lpac_context_t lpac_ctx = (lpac_context_t)ctx->userdata;
    if (lpac_ctx->apdu_interface.logical_channel_open)
    {
        int ret = lpac_ctx->apdu_interface.logical_channel_open(aid, aid_len, lpac_ctx->user_data);
        lpac_ctx->logical_channel_id = ret;
        return ret;
    }
    return -1;
}

static void apdu_interface_logical_channel_close(struct euicc_ctx *ctx, uint8_t channel)
{
    lpac_context_t lpac_ctx = (lpac_context_t)ctx->userdata;
    if (lpac_ctx->apdu_interface.logical_channel_close)
    {
        lpac_ctx->apdu_interface.logical_channel_close(channel, lpac_ctx->user_data);
    }
}

static int apdu_interface_transmit(struct euicc_ctx *ctx, uint8_t **rx, uint32_t *rx_len,
                                   const uint8_t *tx, uint32_t tx_len)
{
    lpac_context_t lpac_ctx = (lpac_context_t)ctx->userdata;
    if (lpac_ctx->apdu_interface.transmit)
    {
        return lpac_ctx->apdu_interface.transmit(rx, rx_len, tx, tx_len, lpac_ctx->user_data);
    }
    return -1;
}

// HTTP interface implementation
static int http_interface_transmit(struct euicc_ctx *ctx, const char *url, uint32_t *rcode,
                                   uint8_t **rx, uint32_t *rx_len, const uint8_t *tx,
                                   uint32_t tx_len, const char **headers)
{
    lpac_context_t lpac_ctx = (lpac_context_t)ctx->userdata;
    if (lpac_ctx->http_interface.transmit)
    {
        return lpac_ctx->http_interface.transmit(url, rcode, rx, rx_len, tx, tx_len,
                                                 headers, lpac_ctx->user_data);
    }
    return -1;
}

// Interface structures for euicc library
static struct euicc_apdu_interface euicc_apdu_interface = {
    .connect = apdu_interface_connect,
    .disconnect = apdu_interface_disconnect,
    .logic_channel_open = apdu_interface_logical_channel_open,
    .logic_channel_close = apdu_interface_logical_channel_close,
    .transmit = apdu_interface_transmit};

static struct euicc_http_interface euicc_http_interface = {
    .transmit = http_interface_transmit};

// Implementation of public API functions

lpac_context_t lpac_create_context(const uint8_t *isdr_aid, uint32_t isdr_len,
                                   lpac_apdu_interface_t *apdu_interface,
                                   lpac_http_interface_t *http_interface,
                                   void *user_data)
{
    lpac_context_t ctx = calloc(1, sizeof(struct lpac_context));
    if (!ctx)
    {
        return NULL;
    }

    // Copy AID
    ctx->aid = malloc(isdr_len);
    if (!ctx->aid)
    {
        free(ctx);
        return NULL;
    }
    memcpy(ctx->aid, isdr_aid, isdr_len);
    ctx->aid_len = isdr_len;

    // Copy interfaces if provided
    if (apdu_interface)
    {
        memcpy(&ctx->apdu_interface, apdu_interface, sizeof(lpac_apdu_interface_t));
    }

    if (http_interface)
    {
        memcpy(&ctx->http_interface, http_interface, sizeof(lpac_http_interface_t));
    }

    ctx->user_data = user_data;

    // Set up euicc context
    ctx->euicc_ctx.apdu.interface = &euicc_apdu_interface;
    ctx->euicc_ctx.http.interface = &euicc_http_interface;
    ctx->euicc_ctx.aid = ctx->aid;
    ctx->euicc_ctx.aid_len = ctx->aid_len;
    ctx->euicc_ctx.userdata = ctx;

    return ctx;
}

void lpac_destroy_context(lpac_context_t ctx)
{
    if (ctx)
    {
        free(ctx->aid);
        free(ctx);
    }
}

lpac_error_t lpac_init(lpac_context_t ctx)
{
    if (!ctx)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = euicc_init(&ctx->euicc_ctx);
    return ret == 0 ? LPAC_SUCCESS : LPAC_ERROR_GENERAL;
}

void lpac_fini(lpac_context_t ctx)
{
    if (ctx)
    {
        euicc_fini(&ctx->euicc_ctx);
    }
}

void lpac_set_mss(lpac_context_t ctx, uint8_t mss)
{
    if (ctx)
    {
        ctx->euicc_ctx.es10x_mss = mss;
    }
}

lpac_error_t lpac_get_eid(lpac_context_t ctx, char **eid)
{
    if (!ctx || !eid)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    *eid = NULL;
    char *buf = NULL;
    int ret = es10c_get_eid(&ctx->euicc_ctx, &buf);

    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    *eid = strdup(buf);
    free(buf);

    return LPAC_SUCCESS;
}

// More implementation functions would follow...

// For example:
lpac_error_t lpac_get_profiles_info(lpac_context_t ctx, lpac_profile_list_t **profiles)
{
    if (!ctx || !profiles)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    struct es10c_profile_info_list *info = NULL;
    int ret = es10c_get_profiles_info(&ctx->euicc_ctx, &info);

    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    // Count profiles
    int count = 0;
    struct es10c_profile_info_list *curr = info;
    while (curr)
    {
        count++;
        curr = curr->next;
    }

    // Allocate result structure
    lpac_profile_list_t *result = calloc(1, sizeof(lpac_profile_list_t));
    if (!result)
    {
        es10c_profile_info_list_free_all(info);
        return LPAC_ERROR_MEMORY;
    }

    // Allocate profiles array
    result->count = count;
    result->profiles = calloc(count, sizeof(lpac_profile_info_t));
    if (!result->profiles)
    {
        free(result);
        es10c_profile_info_list_free_all(info);
        return LPAC_ERROR_MEMORY;
    }

    // Copy profile data
    curr = info;
    for (int i = 0; i < count; i++)
    {
        if (curr->iccid)
            result->profiles[i].iccid = strdup(curr->iccid);
        if (curr->profileName)
            result->profiles[i].name = strdup(curr->profileName);
        if (curr->serviceProviderName)
            result->profiles[i].provider = strdup(curr->serviceProviderName);
        if (curr->profileNickname)
            result->profiles[i].nickname = strdup(curr->profileNickname);
        if (curr->isdpAid)
            result->profiles[i].isdp_aid = strdup(curr->isdpAid);

        result->profiles[i].state = curr->profileState;
        result->profiles[i].profile_class = curr->profileClass;

        curr = curr->next;
    }

    es10c_profile_info_list_free_all(info);
    *profiles = result;
    return LPAC_SUCCESS;
}

void lpac_free_profile_list(lpac_profile_list_t *profiles)
{
    if (!profiles)
    {
        return;
    }

    for (int i = 0; i < profiles->count; i++)
    {
        free(profiles->profiles[i].iccid);
        free(profiles->profiles[i].name);
        free(profiles->profiles[i].provider);
        free(profiles->profiles[i].nickname);
        free(profiles->profiles[i].isdp_aid);
    }

    free(profiles->profiles);
    free(profiles);
}

void lpac_free_string(char *str)
{
    free(str);
}
// ...existing code...

lpac_error_t lpac_enable_profile(lpac_context_t ctx, const char *iccid, bool refresh)
{
    if (!ctx || !iccid)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es10c_enable_profile(&ctx->euicc_ctx, iccid, refresh ? 1 : 0);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}

lpac_error_t lpac_disable_profile(lpac_context_t ctx, const char *iccid, bool refresh)
{
    if (!ctx || !iccid)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es10c_disable_profile(&ctx->euicc_ctx, iccid, refresh ? 1 : 0);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}

lpac_error_t lpac_delete_profile(lpac_context_t ctx, const char *iccid)
{
    if (!ctx || !iccid)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es10c_delete_profile(&ctx->euicc_ctx, iccid);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}

lpac_error_t lpac_set_nickname(lpac_context_t ctx, const char *iccid, const char *nickname)
{
    if (!ctx || !iccid || !nickname)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es10c_set_nickname(&ctx->euicc_ctx, iccid, nickname);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}
#ifndef ES9P_DOWNLOAD_EVENT_DEFINED
#define ES9P_DOWNLOAD_EVENT_DEFINED
enum es9p_download_event {
    ES9P_DOWNLOAD_BOUND_PROFILE_PACKAGE,
    ES9P_DOWNLOAD_CONNECTING,
    ES9P_DOWNLOAD_AUTHENTICATING,
    ES9P_DOWNLOAD_DOWNLOADING,
    ES9P_DOWNLOAD_FINALIZING
    // Add any other states that might be in the original definition
};
#endif
// Callback for profile download progress
static void download_cb_wrapper(enum es9p_download_event event, void* userdata) {
    download_callback_data_t* data = (download_callback_data_t*)userdata;
    
    if (!data || !data->callback)
    {
        return;
    }
    
    lpac_download_state_t state;
    
    switch (event)
    {
        case ES9P_DOWNLOAD_BOUND_PROFILE_PACKAGE:
            state = LPAC_DOWNLOAD_STATE_PREPARING;
            break;
        case ES9P_DOWNLOAD_CONNECTING:
            state = LPAC_DOWNLOAD_STATE_CONNECTING;
            break;
        case ES9P_DOWNLOAD_AUTHENTICATING:
            state = LPAC_DOWNLOAD_STATE_AUTHENTICATING;
            break;
        case ES9P_DOWNLOAD_DOWNLOADING:
            state = LPAC_DOWNLOAD_STATE_DOWNLOADING;
            break;
        case ES9P_DOWNLOAD_FINALIZING:
            state = LPAC_DOWNLOAD_STATE_FINALIZING;
            break;
        default:
            return;
    }
    
    data->callback(state, data->user_data);
}

lpac_error_t lpac_download_profile(lpac_context_t ctx,
                                   const char* smdp,
                                   const char* matching_id,
                                   const char* imei,
                                   const char* confirmation_code,
                                   lpac_download_callback_t callback,
                                   void* user_data)
{
    if (!ctx || !smdp)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }
    
    struct es10b_load_bound_profile_package_result result;
    int ret;
    download_callback_data_t callback_data;
    
    // Store callback information if provided
    if (callback) {
        callback_data.callback = callback;
        callback_data.user_data = user_data;
    }
    
    // Set server address
    ctx->euicc_ctx.http.server_address = smdp;
    
    // PREPARING phase
    if (callback) {
        download_cb_wrapper(ES9P_DOWNLOAD_BOUND_PROFILE_PACKAGE, &callback_data);
    }
    
    ret = es10b_get_euicc_challenge_and_info(&ctx->euicc_ctx);
    if (ret < 0) {
        return LPAC_ERROR_GENERAL;
    }
    
    // CONNECTING phase
    if (callback) {
        download_cb_wrapper(ES9P_DOWNLOAD_CONNECTING, &callback_data);
    }
    
    ret = es9p_initiate_authentication(&ctx->euicc_ctx);
    if (ret < 0) {
        return LPAC_ERROR_COMMUNICATION;
    }
    
    // AUTHENTICATING phase
    if (callback) {
        download_cb_wrapper(ES9P_DOWNLOAD_AUTHENTICATING, &callback_data);
    }
    
    ret = es10b_authenticate_server(&ctx->euicc_ctx, matching_id, imei);
    if (ret < 0) {
        return LPAC_ERROR_AUTHENTICATION;
    }
    
    ret = es9p_authenticate_client(&ctx->euicc_ctx);
    if (ret < 0) {
        return LPAC_ERROR_AUTHENTICATION;
    }
    
    // DOWNLOADING phase
    if (callback) {
        download_cb_wrapper(ES9P_DOWNLOAD_DOWNLOADING, &callback_data);
    }
    
    ret = es10b_prepare_download(&ctx->euicc_ctx, confirmation_code);
    if (ret < 0) {
        return LPAC_ERROR_GENERAL;
    }
    
    ret = es9p_get_bound_profile_package(&ctx->euicc_ctx);
    if (ret < 0) {
        return LPAC_ERROR_COMMUNICATION;
    }
    
    // FINALIZING phase
    if (callback) {
        download_cb_wrapper(ES9P_DOWNLOAD_FINALIZING, &callback_data);
    }
    
    ret = es10b_load_bound_profile_package(&ctx->euicc_ctx, &result);
    if (ret < 0) {
        // Map the detailed error code if needed
        return LPAC_ERROR_PROFILE;
    }
    
    return LPAC_SUCCESS;
}
void lpac_cancel_sessions(lpac_context_t ctx)
{
    if (ctx)
    {
        es9p_cancel_session(&ctx->euicc_ctx);
    }
}

const char* lpac_download_error_to_string(int error_code)
{
    switch (error_code) {
        case ES10B_ERROR_REASON_INCORRECT_INPUT_VALUES:
            return "INCORRECT_INPUT_VALUES";
        case ES10B_ERROR_REASON_INVALID_SIGNATURE:
            return "INVALID_SIGNATURE";
        case ES10B_ERROR_REASON_INVALID_TRANSACTION_ID:
            return "INVALID_TRANSACTION_ID";
        case ES10B_ERROR_REASON_UNSUPPORTED_CRT_VALUES:
            return "UNSUPPORTED_CRT_VALUES";
        case ES10B_ERROR_REASON_UNSUPPORTED_REMOTE_OPERATION_TYPE:
            return "UNSUPPORTED_REMOTE_OPERATION_TYPE";
        case ES10B_ERROR_REASON_UNSUPPORTED_PROFILE_CLASS:
            return "UNSUPPORTED_PROFILE_CLASS";
        case ES10B_ERROR_REASON_SCP03T_STRUCTURE_ERROR:
            return "SCP03T_STRUCTURE_ERROR";
        case ES10B_ERROR_REASON_SCP03T_SECURITY_ERROR:
            return "SCP03T_SECURITY_ERROR";
        case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_ICCID_ALREADY_EXISTS_ON_EUICC:
            return "INSTALL_FAILED_DUE_TO_ICCID_ALREADY_EXISTS_ON_EUICC";
        case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_INSUFFICIENT_MEMORY_FOR_PROFILE:
            return "INSTALL_FAILED_DUE_TO_INSUFFICIENT_MEMORY_FOR_PROFILE";
        case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_INTERRUPTION:
            return "INSTALL_FAILED_DUE_TO_INTERRUPTION";
        case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_PE_PROCESSING_ERROR:
            return "INSTALL_FAILED_DUE_TO_PE_PROCESSING_ERROR";
        case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_ICCID_MISMATCH:
            return "INSTALL_FAILED_DUE_TO_ICCID_MISMATCH";
        case ES10B_ERROR_REASON_TEST_PROFILE_INSTALL_FAILED_DUE_TO_INVALID_NAA_KEY:
            return "TEST_PROFILE_INSTALL_FAILED_DUE_TO_INVALID_NAA_KEY";
        case ES10B_ERROR_REASON_PPR_NOT_ALLOWED:
            return "PPR_NOT_ALLOWED";
        case ES10B_ERROR_REASON_INSTALL_FAILED_DUE_TO_UNKNOWN_ERROR:
            return "INSTALL_FAILED_DUE_TO_UNKNOWN_ERROR";
        default:
            return "ES10B_ERROR_REASON_UNDEFINED";
    }
}

lpac_error_t lpac_list_notifications(lpac_context_t ctx, lpac_notification_list_t **notifications)
{
    if (!ctx || !notifications)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    struct es10b_notification_metadata_list *notif_list = NULL;
    int ret = es10b_list_notification(&ctx->euicc_ctx, &notif_list);

    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    // Count notifications
    int count = 0;
    struct es10b_notification_metadata_list *curr = notif_list;
    while (curr)
    {
        count++;
        curr = curr->next;
    }

    // Allocate result structure
    lpac_notification_list_t *result = calloc(1, sizeof(lpac_notification_list_t));
    if (!result)
    {
        es10b_notification_metadata_list_free_all(notif_list);
        return LPAC_ERROR_MEMORY;
    }

    // Allocate notifications array
    result->count = count;
    result->notifications = calloc(count, sizeof(lpac_notification_t));
    if (!result->notifications)
    {
        free(result);
        es10b_notification_metadata_list_free_all(notif_list);
        return LPAC_ERROR_MEMORY;
    }

    // Copy notification data
    curr = notif_list;
    for (int i = 0; i < count; i++)
    {
        result->notifications[i].seq_number = curr->seqNumber;
        if (curr->notificationAddress)
        {
            result->notifications[i].notification_address = strdup(curr->notificationAddress);
        }
        if (curr->iccid)
        {
            result->notifications[i].iccid = strdup(curr->iccid);
        }

        // Map profile management operation
        if (curr->profileManagementOperation == ES10B_PROFILE_MANAGEMENT_OPERATION_INSTALL)
        {
            result->notifications[i].operation = 1; // install
        }
        else if (curr->profileManagementOperation == ES10B_PROFILE_MANAGEMENT_OPERATION_DELETE)
        {
            result->notifications[i].operation = 2; // delete
        }
        else if (curr->profileManagementOperation == ES10B_PROFILE_MANAGEMENT_OPERATION_ENABLE)
        {
            result->notifications[i].operation = 3; // enable
        }
        else if (curr->profileManagementOperation == ES10B_PROFILE_MANAGEMENT_OPERATION_DISABLE)
        {
            result->notifications[i].operation = 4; // disable
        }
        else
        {
            result->notifications[i].operation = 0; // unknown
        }

        curr = curr->next;
    }

    es10b_notification_metadata_list_free_all(notif_list);
    *notifications = result;
    return LPAC_SUCCESS;
}

void lpac_free_notification_list(lpac_notification_list_t *notifications)
{
    if (!notifications)
    {
        return;
    }

    for (int i = 0; i < notifications->count; i++)
    {
        free(notifications->notifications[i].notification_address);
        free(notifications->notifications[i].iccid);
    }

    free(notifications->notifications);
    free(notifications);
}

lpac_error_t lpac_handle_notification(lpac_context_t ctx, uint64_t seq_number)
{
    if (!ctx)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es9p_handle_notification(&ctx->euicc_ctx, seq_number);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}

lpac_error_t lpac_delete_notification(lpac_context_t ctx, uint64_t seq_number)
{
    if (!ctx)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es10b_remove_notification_from_list(&ctx->euicc_ctx, seq_number);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}

// Utility function to copy a NULL-terminated array of char*
char **copy_string_array(char **source) {
    if (!source) {
        return NULL;
    }
    
    // Count the number of elements in the source array
    int count = 0;
    while (source[count]) {
        count++;
    }
    
    // Allocate memory for the destination array
    char **dest = malloc((count + 1) * sizeof(char *));
    if (!dest) {
        return NULL;
    }
    
    // Copy each string
    for (int i = 0; i < count; i++) {
        dest[i] = strdup(source[i]);
        if (!dest[i]) {
            // Free already allocated strings in case of failure
            for (int j = 0; j < i; j++) {
                free(dest[j]);
            }
            free(dest);
            return NULL;
        }
    }
    
    // NULL-terminate the destination array
    dest[count] = NULL;
    
    return dest;
}
lpac_error_t lpac_get_euicc_info(lpac_context_t ctx, lpac_euicc_info2 **info)
{
    if (!ctx || !info)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }
    
    struct es10c_ex_euiccinfo2 *euicc_info = malloc(sizeof(struct es10c_ex_euiccinfo2));
    int ret = es10c_ex_get_euiccinfo2(&ctx->euicc_ctx, euicc_info);
    
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }
    
    lpac_euicc_info2 *card_info = calloc(1, sizeof(lpac_euicc_info2));
    if (!card_info)
    {
        es10c_ex_euiccinfo2_free(euicc_info);
        return LPAC_ERROR_MEMORY;
    }
    
    // Copy fields
    
    if (euicc_info->profileVersion)
    {
        card_info->profileVersion = strdup(euicc_info->profileVersion);
    }
    if (euicc_info->euiccFirmwareVer)
    {
        card_info->euiccFirmwareVer = strdup(euicc_info->euiccFirmwareVer);
    }
    if (euicc_info->svn)
    {
        card_info->svn = strdup(euicc_info->svn);
    }
    if (euicc_info->euiccFirmwareVer)
    {
        card_info->euiccFirmwareVer = strdup(euicc_info->euiccFirmwareVer);
    }
   
    if (euicc_info->ts102241Version)
    {
        card_info->ts102241Version = strdup(euicc_info->ts102241Version);
    }
    
    if (euicc_info->globalplatformVersion)
    {
        card_info->globalplatformVersion = strdup(euicc_info->globalplatformVersion);
    }
    if (euicc_info->rspCapability) {
        card_info->rspCapability = copy_string_array(euicc_info->rspCapability);
    }
    if (euicc_info->euiccCiPKIdListForVerification) {
    
        card_info->euiccCiPKIdListForVerification =  copy_string_array(euicc_info->euiccCiPKIdListForVerification);
    }
    if (euicc_info->euiccCiPKIdListForSigning) {
        card_info->euiccCiPKIdListForSigning = copy_string_array(euicc_info->euiccCiPKIdListForSigning);
    }
    
    if (euicc_info->forbiddenProfilePolicyRules) {
        card_info->forbiddenProfilePolicyRules = copy_string_array(euicc_info->forbiddenProfilePolicyRules);
    }
    if (euicc_info->uiccCapability) {
        card_info->uiccCapability = copy_string_array(euicc_info->uiccCapability);
    }
   
    if (euicc_info->euiccCategory)
    {
        card_info->euiccCategory = strdup(euicc_info->euiccCategory);
    }
   
    if (euicc_info->ppVersion)
    {
        card_info->ppVersion = strdup(euicc_info->ppVersion);
    }
    if (euicc_info->sasAcreditationNumber)
    {
        card_info->sasAcreditationNumber = strdup(euicc_info->sasAcreditationNumber);
    }
    
    if (euicc_info->extCardResource.installedApplication)
    {
        card_info->installedApplication = euicc_info->extCardResource.installedApplication;
    }
    if (euicc_info->extCardResource.freeNonVolatileMemory)
    {
        card_info->freeNonVolatileMemory = euicc_info->extCardResource.freeNonVolatileMemory;
    }
    if (euicc_info->extCardResource.freeVolatileMemory)
    {
        card_info->freeVolatileMemory = euicc_info->extCardResource.freeVolatileMemory;
    }
    if (euicc_info->certificationDataObject.platformLabel)
    {
        card_info->certificationDataObject.platformLabel = euicc_info->certificationDataObject.platformLabel;
    }
    if (euicc_info->certificationDataObject.discoveryBaseURL)
    {
        card_info->certificationDataObject.discoveryBaseURL = strdup(euicc_info->certificationDataObject.discoveryBaseURL);
    }
    
    es10c_ex_euiccinfo2_free(euicc_info);
    *info = card_info;
    
    return LPAC_SUCCESS;
}
void lpac_free_euicc_info(lpac_euicc_info2 *info)
{
    if (!info)
    {
        return;
    }
    
    free(info->profileVersion);
    free(info->euiccFirmwareVer);
    free(info->svn);
    free(info->uiccCapability);
    free(info->ts102241Version);
    free(info->globalplatformVersion);
    free(info->rspCapability);
    free(info->euiccCiPKIdListForVerification);
    free(info->euiccCiPKIdListForSigning);
//    free(info->euiccCategory);
    free(info->forbiddenProfilePolicyRules);
    free(info->ppVersion);
    free(info->sasAcreditationNumber);
    free(info->certificationDataObject.platformLabel);
    free(info->certificationDataObject.discoveryBaseURL);
    free(info);
}


lpac_error_t lpac_memory_reset(lpac_context_t ctx)
{
    if (!ctx)
    {
        return LPAC_ERROR_INVALID_PARAMETER;
    }

    int ret = es10c_euicc_memory_reset(&ctx->euicc_ctx);
    if (ret < 0)
    {
        return LPAC_ERROR_GENERAL;
    }

    return LPAC_SUCCESS;
}
