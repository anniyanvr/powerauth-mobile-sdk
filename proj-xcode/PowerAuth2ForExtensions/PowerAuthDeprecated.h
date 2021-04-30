/*
 * Copyright 2021 Wultra s.r.o.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <PowerAuth2ForExtensions/PowerAuthErrorConstants.h>
#import <PowerAuth2ForExtensions/PowerAuthKeychain.h>
#import <PowerAuth2ForExtensions/PowerAuthKeychainConfiguration.h>
#import <PowerAuth2ForExtensions/PowerAuthLog.h>
#import <PowerAuth2ForExtensions/PowerAuthSystem.h>

// PA2Error*

/** Deprecated, use PowerAuthErrorDomain constant instead. */
PA2_EXTERN_C NSString * __nonnull const PA2ErrorDomain PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorInfoKey_AdditionalInfo constant instead. */
PA2_EXTERN_C NSString * __nonnull const PA2ErrorInfoKey_AdditionalInfo PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorInfoKey_ResponseData constant instead. */
PA2_EXTERN_C NSString * __nonnull const PA2ErrorInfoKey_ResponseData PA2_DEPRECATED(1.6.0);

/** Deprecated, use PowerAuthErrorCode_NetworkError enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeNetworkError PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_SignatureError enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeSignatureError PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_InvalidActivationState enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeInvalidActivationState PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_InvalidActivationData enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeInvalidActivationData PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_MissingActivation enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeMissingActivation PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_ActivationPending enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeActivationPending PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_BiometryNotAvailable enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeBiometryNotAvailable PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_BiometryCancel enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeBiometryCancel PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_BiometryFailed enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeBiometryFailed PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_OperationCancelled enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeOperationCancelled PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_Encryption enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeEncryption PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_WrongParameter enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeWrongParameter PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_InvalidToken enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeInvalidToken PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_WatchConnectivity enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeWatchConnectivity PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_ProtocolUpgrade enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodeProtocolUpgrade PA2_DEPRECATED(1.6.0);
/** Deprecated, use PowerAuthErrorCode_PendingProtocolUpgrade enum instead. */
PA2_EXTERN_C NSInteger const PA2ErrorCodePendingProtocolUpgrade PA2_DEPRECATED(1.6.0);


// PA2Keychain*

/**
 The PA2KeychainConfiguration class is now deprecated, please use PowerAuthKeychainConfiguration as a replacement.
 */
typedef PowerAuthKeychainConfiguration PA2KeychainConfiguration PA2_DEPRECATED(1.6.0);

PA2_EXTERN_C NSString * __nonnull const PA2Keychain_Initialized PA2_DEPRECATED(1.6.0);
PA2_EXTERN_C NSString * __nonnull const PA2Keychain_Status PA2_DEPRECATED(1.6.0);
PA2_EXTERN_C NSString * __nonnull const PA2Keychain_Possession PA2_DEPRECATED(1.6.0);
PA2_EXTERN_C NSString * __nonnull const PA2Keychain_Biometry PA2_DEPRECATED(1.6.0);
PA2_EXTERN_C NSString * __nonnull const PA2Keychain_TokenStore PA2_DEPRECATED(1.6.0);
PA2_EXTERN_C NSString * __nonnull const PA2KeychainKey_Possession PA2_DEPRECATED(1.6.0);

/**
 The PA2Keychain class is now deprecated, please use PowerAuthKeychain as a replacement.
 */
typedef PowerAuthKeychain PA2Keychain PA2_DEPRECATED(1.6.0);
/**
 The PA2KeychainItemAccess is now deprecated, please use PowerAuthKeychainItemAccess as a replacement.
 */
typedef PowerAuthKeychainItemAccess PA2KeychainItemAccess PA2_DEPRECATED(1.6.0);
/**
 The PA2BiometricAuthenticationInfo is now deprecated, please use PowerAuthBiometricAuthenticationInfo as a replacement.
 */
typedef PowerAuthBiometricAuthenticationInfo PA2BiometricAuthenticationInfo PA2_DEPRECATED(1.6.0);
/**
 The PA2BiometricAuthenticationStatus is now deprecated, please use PowerAuthBiometricAuthenticationStatus as a replacement.
 */
typedef PowerAuthBiometricAuthenticationStatus PA2BiometricAuthenticationStatus PA2_DEPRECATED(1.6.0);
/**
 The PA2BiometricAuthenticationType is now deprecated, please use PowerAuthBiometricAuthenticationType as a replacement.
 */
typedef PowerAuthBiometricAuthenticationType PA2BiometricAuthenticationType PA2_DEPRECATED(1.6.0);

// PA2System

/**
 The PA2ExtensionLibrary class is now deprecated, please use PowerAuthSystem as a replacement.
 */
typedef PowerAuthSystem PA2ExtensionLibrary PA2_DEPRECATED(1.6.0);

// PA2Log

/**
 The PA2LogSetEnabled() function is deprecated, please use PowerAuthLogSetEnabled() instead.
 */
PA2_DEPRECATED(1.6.0) PA2_EXTERN_C void PA2LogSetEnabled(BOOL enabled);
/**
 The PA2LogIsEnabled() function is deprecated, please use PowerAuthLogIsEnabled() instead.
 */
PA2_DEPRECATED(1.6.0) PA2_EXTERN_C BOOL PA2LogIsEnabled(void);
/**
 The PA2LogSetVerbose() function is deprecated, please use PowerAuthLogSetVerbose() instead.
 */
PA2_DEPRECATED(1.6.0) PA2_EXTERN_C void PA2LogSetVerbose(BOOL verbose);
/**
 The PA2LogIsVerbose() function is deprecated, please use PowerAuthLogIsVerbose() instead.
 */
PA2_DEPRECATED(1.6.0) PA2_EXTERN_C BOOL PA2LogIsVerbose(void);
