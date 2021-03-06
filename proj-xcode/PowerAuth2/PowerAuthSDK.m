/**
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

#import <PowerAuth2/PowerAuthSDK.h>
#import <PowerAuth2/PowerAuthKeychain.h>
#import <PowerAuth2/PowerAuthSystem.h>
#import <PowerAuth2/PowerAuthLog.h>

#import "PowerAuthSDK+Private.h"

#import "PA2HttpClient.h"
#import "PA2RestApiObjects.h"
#import "PA2AsyncOperation.h"
#import "PA2ObjectSerialization.h"

#import "PA2PrivateTokenKeychainStore.h"
#import "PA2PrivateHttpTokenProvider.h"
#import "PA2PrivateMacros.h"
#import "PA2PrivateEncryptorFactory.h"
#import "PA2GetActivationStatusTask.h"

#if defined(PA2_WATCH_SUPPORT)
#import "PowerAuthWCSessionManager+Private.h"
#endif

#import <UIKit/UIKit.h>

#pragma mark - Constants

/** In case a config is missing, exception with this identifier is thrown. */
NSString *const PowerAuthExceptionMissingConfig = @"PowerAuthExceptionMissingConfig";

#pragma mark - PowerAuth SDK implementation

@implementation PowerAuthSDK
{
	id<NSLocking> _lock;
	
	PowerAuthConfiguration * _configuration;
	PowerAuthKeychainConfiguration * _keychainConfiguration;
	PowerAuthClientConfiguration * _clientConfiguration;
	
	PA2HttpClient *_client;
	NSString *_biometryKeyIdentifier;
	PowerAuthKeychain *_statusKeychain;
	PowerAuthKeychain *_sharedKeychain;
	PowerAuthKeychain *_biometryOnlyKeychain;
	PA2PrivateHttpTokenProvider * _remoteHttpTokenProvider;
	
	/// Current pending status task.
	PA2GetActivationStatusTask * _getStatusTask;
}

#pragma mark - Private methods

- (void) initializeWithConfiguration:(PowerAuthConfiguration*)configuration
			   keychainConfiguration:(PowerAuthKeychainConfiguration*)keychainConfiguration
				 clientConfiguration:(PowerAuthClientConfiguration*)clientConfiguration
{
	
	// Check if the configuration was nil
	if (configuration == nil) {
		[PowerAuthSDK throwInvalidConfigurationException];
	}
	
	// Validate that the configuration was set up correctly
	if (![configuration validateConfiguration]) {
		[PowerAuthSDK throwInvalidConfigurationException];
	}
	
	// Exclusive lock
	_lock = [[NSLock alloc] init];
	
	// Make copy of configuration objects
	_configuration = [configuration copy];
	_keychainConfiguration = [(keychainConfiguration ? keychainConfiguration : [PowerAuthKeychainConfiguration sharedInstance]) copy];
	_clientConfiguration = [(clientConfiguration ? clientConfiguration : [PowerAuthClientConfiguration sharedInstance]) copy];
	
	// Prepare identifier for biometry related keys - use instanceId by default, or a custom value if set
	_biometryKeyIdentifier = _configuration.keychainKey_Biometry ? _configuration.keychainKey_Biometry : _configuration.instanceId;
	
	// Create session setup parameters
	PowerAuthCoreSessionSetup *setup = [[PowerAuthCoreSessionSetup alloc] init];
	setup.applicationKey = _configuration.appKey;
	setup.applicationSecret = _configuration.appSecret;
	setup.masterServerPublicKey = _configuration.masterServerPublicKey;
	setup.externalEncryptionKey = _configuration.externalEncryptionKey;
	
	// Create a new session
	_session = [[PowerAuthCoreSession alloc] initWithSessionSetup:setup];
	if (_session == nil) {
		[PowerAuthSDK throwInvalidConfigurationException];
	}
	
	// Create and setup a new client
	_client = [[PA2HttpClient alloc] initWithConfiguration:_clientConfiguration
										   completionQueue:dispatch_get_main_queue()
												   baseUrl:_configuration.baseEndpointUrl
													helper:self];
	
	// Create a new keychain instances
	_statusKeychain			= [[PowerAuthKeychain alloc] initWithIdentifier:_keychainConfiguration.keychainInstanceName_Status
																accessGroup:_keychainConfiguration.keychainAttribute_AccessGroup];
	_sharedKeychain			= [[PowerAuthKeychain alloc] initWithIdentifier:_keychainConfiguration.keychainInstanceName_Possession
																accessGroup:_keychainConfiguration.keychainAttribute_AccessGroup];
	_biometryOnlyKeychain	= [[PowerAuthKeychain alloc] initWithIdentifier:_keychainConfiguration.keychainInstanceName_Biometry];
	// Initialize token store with its own keychain as a backing storage and remote token provider.
	PowerAuthKeychain * tokenStoreKeychain = [[PowerAuthKeychain alloc] initWithIdentifier:_keychainConfiguration.keychainInstanceName_TokenStore
																			   accessGroup:_keychainConfiguration.keychainAttribute_AccessGroup];
	_remoteHttpTokenProvider = [[PA2PrivateHttpTokenProvider alloc] initWithHttpClient:_client];
	_tokenStore = [[PA2PrivateTokenKeychainStore alloc] initWithConfiguration:self.configuration
																	 keychain:tokenStoreKeychain
															   statusProvider:self
															   remoteProvider:_remoteHttpTokenProvider];

	// Make sure to reset keychain data after app re-install.
	// Important: This deletes all Keychain data in all PowerAuthSDK instances!
	// By default, the code uses standard user defaults, use `PowerAuthKeychainConfiguration.keychainAttribute_UserDefaultsSuiteName` to use `NSUserDefaults` with a custom suite name.
	NSUserDefaults *userDefaults = nil;
	if (_keychainConfiguration.keychainAttribute_UserDefaultsSuiteName != nil) {
		userDefaults = [[NSUserDefaults alloc] initWithSuiteName:_keychainConfiguration.keychainAttribute_UserDefaultsSuiteName];
	} else {
		userDefaults = [NSUserDefaults standardUserDefaults];
	}
	if ([userDefaults boolForKey:PowerAuthKeychain_Initialized] == NO) {
		[_statusKeychain deleteAllData];
		[_sharedKeychain deleteAllData];
		[_biometryOnlyKeychain deleteAllData];
		[tokenStoreKeychain deleteAllData];
		[userDefaults setBool:YES forKey:PowerAuthKeychain_Initialized];
		[userDefaults synchronize];
	}
	
	// Attempt to restore session state
	[self restoreState];
	
#if defined(PA2_WATCH_SUPPORT)
	// Register this instance to handle messages
	[[PowerAuthWCSessionManager sharedInstance] registerDataHandler:self];
#endif
}

- (void) dealloc
{
#if defined(PA2_WATCH_SUPPORT)
	// Unregister this instance for processing packets...
	[[PowerAuthWCSessionManager sharedInstance] unregisterDataHandler:self];
#endif
	// Cancel possible get activation status task
	[self cancelActivationStatusTask];
}


+ (void) throwInvalidConfigurationException {
	[NSException raise:PowerAuthExceptionMissingConfig
				format:@"Invalid PowerAuthSDK configuration. You must set a valid PowerAuthConfiguration to PowerAuthSDK instance using initializer."];
}

- (PowerAuthConfiguration*) configuration
{
	return [_configuration copy];
}

- (PowerAuthClientConfiguration*) clientConfiguration
{
	return [_clientConfiguration copy];
}

- (PowerAuthKeychainConfiguration*) keychainConfiguration
{
	return [_keychainConfiguration copy];
}

- (NSString*) privateInstanceId
{
	// Private getter, used inside the IOS-SDK
	return _configuration.instanceId;
}

/**
 This private method checks for valid PowerAuthCoreSessionSetup and throws a PowerAuthExceptionMissingConfig exception when the provided configuration
 is not correct or is missing.
 */
- (void) checkForValidSetup
{
	if (!_session.hasValidSetup) {
		[PowerAuthSDK throwInvalidConfigurationException];
	}
}

#pragma mark - Key management

- (NSData*) deviceRelatedKey
{
	// Cache the possession key in the keychain
	NSData * possessionKey = [_sharedKeychain dataForKey:_keychainConfiguration.keychainKey_Possession status:nil];
	if (nil == possessionKey) {
		NSString *uuidString;
#if TARGET_IPHONE_SIMULATOR
		uuidString = @"ffa184f9-341a-444f-8495-de04d0d490be";
#else
		uuidString = [UIDevice currentDevice].identifierForVendor.UUIDString;
#endif
		NSData *uuidData = [uuidString dataUsingEncoding:NSUTF8StringEncoding];
		possessionKey = [PowerAuthCoreSession normalizeSignatureUnlockKeyFromData:uuidData];
		[_sharedKeychain addValue:possessionKey forKey:_keychainConfiguration.keychainKey_Possession];
	}
	return possessionKey;
}

- (NSData*) biometryRelatedKeyUserCancelled:(nullable BOOL *)userCancelled prompt:(NSString*)prompt {
	if ([_biometryOnlyKeychain containsDataForKey:_biometryKeyIdentifier]) {
		__block OSStatus status = errSecUserCanceled;
		__block NSData *key = nil;
		BOOL executed = [PowerAuthKeychain tryLockBiometryAndExecuteBlock:^{
			key = [_biometryOnlyKeychain dataForKey:_biometryKeyIdentifier status:&status prompt:prompt];
		}];
		if (userCancelled != NULL) {
			if (!executed || status == errSecUserCanceled) {
				*userCancelled = YES;
			} else {
				*userCancelled = NO;
			}
		}
		return key;
	} else {
		if (userCancelled != NULL) {
			*userCancelled = NO;
		}
		return nil;
	}
}

- (PowerAuthCoreSignatureUnlockKeys*) signatureKeysForAuthentication:(PowerAuthAuthentication*)authentication
													   userCancelled:(nonnull BOOL *)userCancelled
{
	// Generate signature key encryption keys
	NSData *possessionKey = nil;
	NSData *biometryKey = nil;
	PowerAuthCorePassword *knowledgeKey = nil;
	if (authentication.usePossession) {
		if (authentication.overridenPossessionKey) {
			possessionKey = authentication.overridenPossessionKey;
		} else {
			possessionKey = [self deviceRelatedKey];
		}
	}
	if (authentication.useBiometry) {
		if (authentication.overridenBiometryKey) { // user specified a custom biometry key
			biometryKey = authentication.overridenBiometryKey;
		} else { // default biometry key should be fetched
			biometryKey = [self biometryRelatedKeyUserCancelled:userCancelled prompt:authentication.biometryPrompt];
			if (*userCancelled) {
				return nil;
			}
			// If the key was not fetched (and not because of user cancel action) and biometry
			// was requested, generate a "fake key" so that signature can silently fail
			else {
				if (biometryKey == nil) {
					PowerAuthLog(@"ERROR! Biometric authentication failed or there's no biometric key in the keychain.");
					biometryKey = [PowerAuthCoreSession generateSignatureUnlockKey];
				}
			}
		}
	}
	if (authentication.usePassword) {
		knowledgeKey = [PowerAuthCorePassword passwordWithString:authentication.usePassword];
	}
	
	// Prepare signature unlock keys structure
	PowerAuthCoreSignatureUnlockKeys *keys = [[PowerAuthCoreSignatureUnlockKeys alloc] init];
	keys.possessionUnlockKey = possessionKey;
	keys.biometryUnlockKey = biometryKey;
	keys.userPassword = knowledgeKey;
	return keys;
}

- (PowerAuthCoreSignatureFactor) determineSignatureFactorForAuthentication:(PowerAuthAuthentication*)authentication
{
	PowerAuthCoreSignatureFactor factor = 0;
	if (authentication.usePossession) {
		factor |= PowerAuthCoreSignatureFactor_Possession;
	}
	if (authentication.usePassword != nil) {
		factor |= PowerAuthCoreSignatureFactor_Knowledge;
	}
	if (authentication.useBiometry) {
		factor |= PowerAuthCoreSignatureFactor_Biometry;
	}
	return factor;
}

- (id<PowerAuthOperationTask>) fetchEncryptedVaultUnlockKey:(PowerAuthAuthentication*)authentication
													 reason:(PA2VaultUnlockReason)reason
												   callback:(void(^)(NSString * encryptedEncryptionKey, NSError *error))callback
{
	[self checkForValidSetup];
	// Check if there is an activation present
	if (!_session.hasValidActivation) {
		callback(nil, PA2MakeError(PowerAuthErrorCode_MissingActivation, nil));
		return nil;
	}
	return [_client postObject:[[PA2VaultUnlockRequest alloc] initWithReason:reason]
							to:[PA2RestApiEndpoint vaultUnlock]
						  auth:authentication
					completion:^(PowerAuthRestApiResponseStatus status, id<PA2Decodable> response, NSError *error) {
						NSString * encryptedEncryptionKey = nil;
						if (status == PowerAuthRestApiResponseStatus_OK) {
							PA2VaultUnlockResponse * ro = response;
							encryptedEncryptionKey = ro.encryptedVaultEncryptionKey;
						}
						if (!encryptedEncryptionKey && !error) {
							// fallback to error
							error = PA2MakeError(PowerAuthErrorCode_InvalidActivationState, nil);
						}
						callback(encryptedEncryptionKey, error);
					}];
}

#pragma mark - Public methods

#pragma mark Initializers and SDK instance getters

static PowerAuthSDK * s_inst;

- (nullable instancetype) initWithConfiguration:(nonnull PowerAuthConfiguration *)configuration
						  keychainConfiguration:(nullable PowerAuthKeychainConfiguration *)keychainConfiguration
							clientConfiguration:(nullable PowerAuthClientConfiguration *)clientConfiguration
{
	self = [super init];
	if (self) {
		[self initializeWithConfiguration:configuration
					keychainConfiguration:keychainConfiguration
					  clientConfiguration:clientConfiguration];
	}
	return self;
}

- (instancetype)initWithConfiguration:(PowerAuthConfiguration *)configuration
{
	return [self initWithConfiguration:configuration keychainConfiguration:nil clientConfiguration:nil];
}

+ (void) initSharedInstance:(PowerAuthConfiguration*)configuration
{
	[self initSharedInstance:configuration keychainConfiguration:nil clientConfiguration:nil];
}

+ (void) initSharedInstance:(nonnull PowerAuthConfiguration *)configuration
	  keychainConfiguration:(nullable PowerAuthKeychainConfiguration *)keychainConfiguration
		clientConfiguration:(nullable PowerAuthClientConfiguration *)clientConfiguration
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		s_inst = [[PowerAuthSDK alloc] initWithConfiguration:configuration
									   keychainConfiguration:keychainConfiguration
										 clientConfiguration:clientConfiguration];
	});
}

+ (PowerAuthSDK*) sharedInstance
{
	if (!s_inst) {
		[PowerAuthSDK throwInvalidConfigurationException];
	}
	return s_inst;
}

#pragma mark Session state management

- (BOOL) restoreState
{
	NSData *sessionData = [_statusKeychain dataForKey:_configuration.instanceId status:nil];
	if (sessionData) {
		[_session resetSession];
		return [_session deserializeState:sessionData];
	} else {
		return NO;
	}
}

- (void) saveSessionState
{
	[_statusKeychain updateValue:[_session serializedState] forKey:_configuration.instanceId];
}

- (BOOL) canStartActivation
{
	[self checkForValidSetup];
	return _session.canStartActivation;
}

- (BOOL) hasPendingActivation
{
	[self checkForValidSetup];
	return _session.hasPendingActivation;
}

- (BOOL) hasValidActivation
{
	[self checkForValidSetup];
	return _session.hasValidActivation;
}

- (BOOL) hasProtocolUpgradeAvailable
{
	[self checkForValidSetup];
	return _session.hasProtocolUpgradeAvailable;
}

- (BOOL) hasPendingProtocolUpgrade
{
	[self checkForValidSetup];
	return _session.hasPendingProtocolUpgrade;
}


#pragma mark - Activation
#pragma mark Creating a new activation

- (id<PowerAuthOperationTask>) createActivation:(PowerAuthActivation*)activation
									   callback:(void(^)(PowerAuthActivationResult * _Nullable result, NSError * _Nullable error))callback
{
	// Input parameters check
	[self checkForValidSetup];
	
	if (!callback) {
		PowerAuthLog(@"Missing callback in createActivation() method.");
		return nil;
	}
	if (!activation) {
		callback(nil, PA2MakeError(PowerAuthErrorCode_WrongParameter, nil));
		return nil;
	}
	NSError * validationError = [activation validateAndGetError];
	if (validationError) {
		callback(nil, validationError);
		return nil;
	}
	
	// Check if activation can be started
	if (![self canStartActivation]) {
		callback(nil, PA2MakeError(PowerAuthErrorCode_InvalidActivationState, nil));
		return nil;
	}
	
	// Prepare both layers of activation data
	PA2CreateActivationRequest * request = [[PA2CreateActivationRequest alloc] init];
	request.activationType = activation.activationType;
	request.identityAttributes = activation.identityAttributes;
	request.customAttributes = activation.customAttributes;
	
	PA2CreateActivationRequestData * requestData = [[PA2CreateActivationRequestData alloc] init];
	requestData.activationName = activation.name;
	requestData.extras = activation.extras;
	requestData.activationOtp = activation.additionalActivationOtp;
	requestData.platform = [PowerAuthSystem platform];
	requestData.deviceInfo = [PowerAuthSystem deviceInfo];
	
	// Start activation and encrypt both layers of the request data.
	NSError * error = nil;
	PowerAuthCoreEciesEncryptor * decryptor = [self prepareActivation:activation
														   forRequest:request
														  requestData:requestData
																error:&error];
	if (!decryptor) {
		callback(nil, error);
		return nil;
	}
	
	// Now it's everything prepared for sending the request
	return [_client postObject:request
							to:[PA2RestApiEndpoint createActivation]
						  auth:nil
					completion:^(PowerAuthRestApiResponseStatus status, id<PA2Decodable> response, NSError *error) {
						// HTTP request completion
						PowerAuthActivationResult * result = nil;
						if (status == PowerAuthRestApiResponseStatus_OK) {
							// Validate response from the server
							result = [self validateActivationResponse:response
															decryptor:decryptor
																error:&error];
						}
						if (!result && !error) {
							// Fallback, to produce at least some error
							error = PA2MakeError(PowerAuthErrorCode_InvalidActivationData, nil);
						}
						if (error) {
							[_session resetSession];
						}
						// Now call back to the application
						callback(result, error);
						
					} cancel:^{
						// In case of cancel, we need to reset the session. The reset itself is
						// thread safe, but it's good to issue that to the main thread.
						dispatch_async(dispatch_get_main_queue(), ^{
							[_session resetSession];
						});
					}];
}

- (id<PowerAuthOperationTask>) createActivationWithName:(NSString*)name
										 activationCode:(NSString*)activationCode
											   callback:(void(^)(PowerAuthActivationResult *result, NSError *error))callback
{
	return [self createActivationWithName:name activationCode:activationCode extras:nil callback:callback];
}

- (id<PowerAuthOperationTask>) createActivationWithName:(NSString*)name
										 activationCode:(NSString*)activationCode
												 extras:(NSString*)extras
											   callback:(void(^)(PowerAuthActivationResult *result, NSError *error))callback
{
	NSError * error = nil;
	PowerAuthActivation * activation = [[PowerAuthActivation activationWithActivationCode:activationCode name:name error:&error] withExtras:extras];
	if (!activation && callback) {
		// Invalid activation code
		callback(nil, error ? error : PA2MakeError(PowerAuthErrorCode_InvalidActivationData, nil));
		return nil;
	}
	return [self createActivation:activation callback:callback];
}

- (id<PowerAuthOperationTask>) createActivationWithName:(NSString*)name
									 identityAttributes:(NSDictionary<NSString*,NSString*>*)identityAttributes
												 extras:(NSString*)extras
											   callback:(void(^)(PowerAuthActivationResult * result, NSError * error))callback
{
	NSError * error = nil;
	PowerAuthActivation * activation = [[PowerAuthActivation activationWithIdentityAttributes:identityAttributes name:name error:&error] withExtras:extras];
	if (!activation && callback) {
		// Missing identity attributes
		callback(nil, error ? error : PA2MakeError(PowerAuthErrorCode_InvalidActivationData, nil));
		return nil;
	}
	return [self createActivation:activation callback:callback];
}

- (nullable id<PowerAuthOperationTask>) createActivationWithName:(nullable NSString*)name
													recoveryCode:(nonnull NSString*)recoveryCode
															 puk:(nonnull NSString*)puk
														  extras:(nullable NSString*)extras
														callback:(nonnull void(^)(PowerAuthActivationResult * result, NSError * error))callback
{
	NSError * error = nil;
	PowerAuthActivation * activation = [[PowerAuthActivation activationWithRecoveryCode:recoveryCode recoveryPuk:puk name:name error:&error] withExtras:extras];
	if (!activation && callback) {
		// Wrong recovery code or PUK
		callback(nil, error ? error : PA2MakeError(PowerAuthErrorCode_InvalidActivationData, nil));
		return nil;
	}
	return [self createActivation:activation callback:callback];
}

#pragma mark Commit

- (BOOL) commitActivationWithPassword:(NSString*)password
								error:(NSError**)error
{
	PowerAuthAuthentication *authentication = [[PowerAuthAuthentication alloc] init];
	authentication.useBiometry = YES;
	authentication.usePossession = YES;
	authentication.usePassword = password;
	return [self commitActivationWithAuthentication:authentication error:error];
}

- (BOOL) commitActivationWithAuthentication:(PowerAuthAuthentication*)authentication
									  error:(NSError**)error
{
	
	[self checkForValidSetup];
	
	// Check if there is a pending activation present and not an already existing valid activation
	if (!_session.hasPendingActivation) {
		if (error) {
			*error = PA2MakeError(PowerAuthErrorCode_InvalidActivationState, nil);
		}
		return NO;
	}
	
	// Prepare key encryption keys
	NSData *possessionKey = nil;
	NSData *biometryKey = nil;
	PowerAuthCorePassword *knowledgeKey = nil;
	if (authentication.usePossession) {
		possessionKey = [self deviceRelatedKey];
	}
	if (authentication.useBiometry) {
		biometryKey = [PowerAuthCoreSession generateSignatureUnlockKey];
	}
	if (authentication.usePassword) {
		knowledgeKey = [PowerAuthCorePassword passwordWithString:authentication.usePassword];
	}
	
	// Prepare signature unlock keys structure
	PowerAuthCoreSignatureUnlockKeys *keys = [[PowerAuthCoreSignatureUnlockKeys alloc] init];
	keys.possessionUnlockKey = possessionKey;
	keys.biometryUnlockKey = biometryKey;
	keys.userPassword = knowledgeKey;
	
	// Complete the activation
	BOOL result = [_session completeActivation:keys];
	
	// Propagate error
	if (!result && error) {
		*error = PA2MakeError(PowerAuthErrorCode_InvalidActivationState, nil);
	}
	
	// Store keys and session state in Keychain
	if (result) {
		[_statusKeychain deleteDataForKey:_configuration.instanceId];
		[_biometryOnlyKeychain deleteDataForKey:_biometryKeyIdentifier];
		
		[_statusKeychain addValue:_session.serializedState forKey:_configuration.instanceId];
		if (biometryKey) {
			[_biometryOnlyKeychain addValue:biometryKey forKey:_biometryKeyIdentifier access:_keychainConfiguration.biometricItemAccess];
		}
		// Clear TokenStore
		[_tokenStore removeAllLocalTokens];
	}
	
	// Return result
	return result;
}

- (NSString*) activationIdentifier
{
	return _session.activationIdentifier;
}

- (NSString*) activationFingerprint
{
	return _session.activationFingerprint;
}


#pragma mark Private activation

/**
 Private method starts an activation.
 
 The method requires request & request data and if everything's right, then request.activationData
 is prepared and metods returns a new decryptor, required for response decryption.
 */
- (PowerAuthCoreEciesEncryptor*) prepareActivation:(PowerAuthActivation*)activation
										forRequest:(PA2CreateActivationRequest*)request
									   requestData:(PA2CreateActivationRequestData*)requestData
											 error:(NSError**)error
{
	PowerAuthCoreEciesEncryptor * decryptor = nil;
	NSError * localError = nil;
	
	// Prepare data for low level code. Note that "activationCode" is optional and may be nil.
	PowerAuthCoreActivationStep1Param * paramStep1 = [[PowerAuthCoreActivationStep1Param alloc] init];
	paramStep1.activationCode = activation.activationCode.coreActivationCode;

	// Begin with the activation
	PowerAuthCoreActivationStep1Result * resultStep1 = [_session startActivation:paramStep1];
	if (resultStep1) {
		// Keep device's public key in requestData
		requestData.devicePublicKey = resultStep1.devicePublicKey;

		// Now we need to ecrypt request data with the Layer2 encryptor.
		PA2PrivateEncryptorFactory * factory = [[PA2PrivateEncryptorFactory alloc] initWithSession:_session deviceRelatedKey:[self deviceRelatedKey]];
		PowerAuthCoreEciesEncryptor * privateEncryptor = [factory encryptorWithId:PA2EncryptorId_ActivationPayload];
		
		// Encrypt payload and put it directly to the request object.
		request.activationData = [PA2ObjectSerialization encryptObject:requestData
															 encryptor:privateEncryptor
																 error:&localError];
		if (!localError) {
			decryptor = privateEncryptor;
		}
	} else {
		localError = PA2MakeError(PowerAuthErrorCode_InvalidActivationData, nil);
	}
	// Return result & error
	if (error) {
		*error = localError;
	}
	return decryptor;
}

/**
 Private method validates response received from the server.
 In case of success, returns a full activation result object.
 */
- (PowerAuthActivationResult*) validateActivationResponse:(PA2CreateActivationResponse*)response
												decryptor:(PowerAuthCoreEciesEncryptor*)decryptor
													error:(NSError**)error
{
	PowerAuthActivationResult * result = nil;
	NSError * localError = nil;
	PA2CreateActivationResponseData * responseData = [PA2ObjectSerialization decryptObject:response.activationData
																				  forClass:[PA2CreateActivationResponseData class]
																				 decryptor:decryptor
																					 error:&localError];
	if (responseData) {
		// Validate response from the server
		PowerAuthCoreActivationStep2Param * paramStep2 = [[PowerAuthCoreActivationStep2Param alloc] init];
		paramStep2.activationId = responseData.activationId;
		paramStep2.serverPublicKey = responseData.serverPublicKey;
		paramStep2.ctrData = responseData.ctrData;
		PowerAuthActivationRecoveryData * activationRecoveryData = nil;
		if (responseData.activationRecovery) {
			PowerAuthCoreRecoveryData * recoveryData = [[PowerAuthCoreRecoveryData alloc] init];
			recoveryData.recoveryCode = responseData.activationRecovery.recoveryCode;
			recoveryData.puk = responseData.activationRecovery.puk;
			paramStep2.activationRecovery = recoveryData;
			activationRecoveryData = [[PowerAuthActivationRecoveryData alloc] initWithRecoveryData:recoveryData];
		}
		PowerAuthCoreActivationStep2Result * resultStep2 = [_session validateActivationResponse:paramStep2];
		if (resultStep2) {
			// Everything looks OK, we can construct result object.
			result = [[PowerAuthActivationResult alloc] init];
			result.activationFingerprint = resultStep2.activationFingerprint;
			result.customAttributes = response.customAttributes;
			result.activationRecovery = activationRecoveryData;
		} else {
			localError = PA2MakeError(PowerAuthErrorCode_InvalidActivationData, nil);
		}
	}
	// Return result & error
	if (error) {
		*error = localError;
	}
	return result;
}


#pragma mark Getting activations state

- (id<PowerAuthOperationTask>) fetchActivationStatusWithCallback:(void(^)(PowerAuthActivationStatus *status, NSDictionary *customObject, NSError *error))callback
{
	[self checkForValidSetup];
	
	// Check for activation
	if (!_session.hasValidActivation) {
		NSInteger errorCode = _session.hasPendingActivation ? PowerAuthErrorCode_ActivationPending : PowerAuthErrorCode_MissingActivation;
		callback(nil, nil, PA2MakeError(errorCode, nil));
		return nil;
	}
	// Create child task and add it to the status fetcher.
	PA2GetActivationStatusChildTask * task = [[PA2GetActivationStatusChildTask alloc] initWithCompletionQueue:dispatch_get_main_queue() completion:callback];
	[self getActivationStatusWithChildTask:task];
	return task;
}


- (void) getActivationStatusWithChildTask:(PA2GetActivationStatusChildTask*)childTask
{
	PA2GetActivationStatusTask * oldTask = nil;
	[_lock lock];
	{
		if (_getStatusTask) {
			if ([_getStatusTask addChildTask:childTask] == NO) {
				// unable to add child task. This means that current task is going to finish its execution soon,
				// so we need to create a new one.
				oldTask = _getStatusTask;
				_getStatusTask = nil;
			}
		}
		if (!_getStatusTask) {
			// Task doesn't exist. We need to create a new one.
			__weak PowerAuthSDK * weakSelf = self;
			_getStatusTask = [[PA2GetActivationStatusTask alloc] initWithHttpClient:_client
																   deviceRelatedKey:[self deviceRelatedKey]
																			session:_session
																	  sessionChange:^(PowerAuthCoreSession * session) {
																		  [weakSelf saveSessionState];
																	  } completion:^(PA2GetActivationStatusTask * task, PowerAuthActivationStatus* status, NSDictionary* customObject, NSError* error) {
																		  [weakSelf completeActivationStatusTask:task status:status customObject:customObject error:error];
																	  }];
			_getStatusTask.disableUpgrade = _configuration.disableAutomaticProtocolUpgrade;
			[_getStatusTask addChildTask:childTask];
			[_getStatusTask execute];
		}
	}
	[_lock unlock];
	
	if (oldTask) {
		// This is the reference to task which is going to finish its execution soon.
		// The ivar no longer holds the reference to the task, but we should keep that reference
		// for a little bit longer, to guarantee, that we don't destroy that object during its
		// finalization stage.
		[[NSOperationQueue mainQueue] addOperationWithBlock:^{
			// The following call does nothing, because the old task is no longer stored
			// in the `_getStatusTask` ivar. It just guarantees that the object will be alive
			// during waiting to execute the operation block.
			[self completeActivationStatusTask:oldTask status:nil customObject:nil error:nil];
		}];
	}
}


/**
 Completes pending PA2GetActivationStatusTask. The function resets internal `_getStatusTask` ivar,
 but only if it equals to provided "task" object.
 
 @param task task being completed
 */
- (void) completeActivationStatusTask:(PA2GetActivationStatusTask*)task
							   status:(PowerAuthActivationStatus*)status
						 customObject:(NSDictionary*)customObject
								error:(NSError*)error
{
	[_lock lock];
	{
		BOOL updateObjects;
		if (task == _getStatusTask) {
			// Regular processing, only one task was scheduled and it just finished.
			_getStatusTask = nil;
			updateObjects = YES;
		} else {
			// If _getStatusTask is nil, then it menas that last status task has been cancelled.
			// In this case, we should not update the objects.
			// If there's a different PA2GetActivationStatusTask object, then that means
			// that during the finishing our batch, was scheduled the next one. In this situation
			// we still can keep the last received objects, because there was no cancel, or reset.
			updateObjects = _getStatusTask != nil;
		}
		// Update last received objects
		if (!error && status && updateObjects) {
			_lastFetchedActivationStatus = status;
			_lastFetchedCustomObject = customObject;
		}
	}
	[_lock unlock];
}


/**
 Cancels possible pending PA2GetActivationStatusTask. The function can be called only in rare cases,
 like when SDK object is going to reset its local state.
 */
- (void) cancelActivationStatusTask
{
	[_lock lock];
	{
		[_getStatusTask cancel];
		_getStatusTask = nil;
		_lastFetchedActivationStatus = nil;
		_lastFetchedCustomObject = nil;
	}
	[_lock unlock];
}


#pragma mark Removing an activation

- (id<PowerAuthOperationTask>) removeActivationWithAuthentication:(PowerAuthAuthentication*)authentication
														 callback:(void(^)(NSError *error))callback
{
	[self checkForValidSetup];
	return [_client postObject:nil
							to:[PA2RestApiEndpoint removeActivation]
						  auth:authentication
					completion:^(PowerAuthRestApiResponseStatus status, id<PA2Decodable> response, NSError *error) {
						// Network communication completed correctly
						if (status == PowerAuthRestApiResponseStatus_OK) {
							[self removeActivationLocal];
						}
						callback(error);
					}];
}

- (void) removeActivationLocal
{
	[self checkForValidSetup];
	BOOL error = NO;
	if ([_statusKeychain containsDataForKey:_configuration.instanceId]) {
		error = error || ![_statusKeychain deleteDataForKey:_configuration.instanceId];
	}
	if ([_biometryOnlyKeychain containsDataForKey:_biometryKeyIdentifier]) {
		error = error || ![_biometryOnlyKeychain deleteDataForKey:_biometryKeyIdentifier];
	}
	if (error) {
		PowerAuthLog(@"Removing activaton data from keychain failed. We can't recover from this error.");
	}
	[self cancelActivationStatusTask];
	[_tokenStore removeAllLocalTokens];
	[_session resetSession];
}


#pragma mark - Computing signatures

- (PowerAuthAuthorizationHttpHeader*) requestGetSignatureWithAuthentication:(PowerAuthAuthentication*)authentication
																	  uriId:(NSString*)uriId
																	 params:(NSDictionary<NSString*, NSString*>*)params
																	  error:(NSError**)error
{
	NSData *data = [_session prepareKeyValueDictionaryForDataSigning:params];
	return [self requestSignatureWithAuthentication:authentication
											 method:@"GET"
											  uriId:uriId
											   body:data
											  error:error];
}

- (PowerAuthAuthorizationHttpHeader*) requestSignatureWithAuthentication:(PowerAuthAuthentication*)authentication
																  method:(NSString*)method
																   uriId:(NSString*)uriId
																	body:(NSData*)body
																   error:(NSError**)error
{
	if (self.hasPendingProtocolUpgrade) {
		if (error) *error = PA2MakeError(PowerAuthErrorCode_PendingProtocolUpgrade, @"Data signing is temporarily unavailable, due to pending protocol upgrade.");
		return nil;
	}
	PowerAuthCoreHTTPRequestData * requestData = [[PowerAuthCoreHTTPRequestData alloc] init];
	requestData.body = body;
	requestData.method = method;
	requestData.uri = uriId;
	PowerAuthCoreHTTPRequestDataSignature * signature = [self signHttpRequestData:requestData
																   authentication:authentication
																			error:error];
	return [PowerAuthAuthorizationHttpHeader authorizationHeaderWithValue:signature.authHeaderValue];
}

- (NSString*) offlineSignatureWithAuthentication:(PowerAuthAuthentication*)authentication
										   uriId:(NSString*)uriId
											body:(NSData*)body
										   nonce:(NSString*)nonce
										   error:(NSError**)error
{
	if (!nonce) {
		if (error) *error = PA2MakeError(PowerAuthErrorCode_WrongParameter, @"Nonce parameter is missing.");
		return nil;
	}
	
	if (self.hasPendingProtocolUpgrade) {
		if (error) *error = PA2MakeError(PowerAuthErrorCode_PendingProtocolUpgrade, @"Offline data signing is temporarily unavailable, due to pending protocol upgrade.");
		return nil;
	}
	
	PowerAuthCoreHTTPRequestData * requestData = [[PowerAuthCoreHTTPRequestData alloc] init];
	requestData.body = body;
	requestData.method = @"POST";
	requestData.uri = uriId;
	requestData.offlineNonce = nonce;
	PowerAuthCoreHTTPRequestDataSignature * signature = [self signHttpRequestData:requestData
																   authentication:authentication
																			error:error];
	if (signature) {
		return signature.signature;
	}
	return nil;
}


/**
 This private method implements both online & offline signature calculations. Unlike the public interfaces, method accepts
 PA2HTTPRequestData object as a source for data for signing and returns structured PA2HTTPRequestDataSignature object.
 */
- (PowerAuthCoreHTTPRequestDataSignature*) signHttpRequestData:(PowerAuthCoreHTTPRequestData*)requestData
												authentication:(PowerAuthAuthentication*)authentication
														 error:(NSError**)error
{
	[self checkForValidSetup];
	
	// Check if there is an activation present
	if (!_session.hasValidActivation) {
		if (error) {
			*error = PA2MakeError(PowerAuthErrorCode_MissingActivation, nil);
		}
		return nil;
	}
	
	// Determine authentication factor type
	PowerAuthCoreSignatureFactor factor = [self determineSignatureFactorForAuthentication:authentication];
	if (factor == 0) {
		if (error) {
			*error = PA2MakeError(PowerAuthErrorCode_WrongParameter, nil);
		}
		return nil;
	}
	
	// Generate signature key encryption keys
	BOOL userCancelled = NO;
	PowerAuthCoreSignatureUnlockKeys *keys = [self signatureKeysForAuthentication:authentication userCancelled:&userCancelled];
	if (keys == nil) { // Unable to fetch Touch ID related record - maybe user or iOS canacelled the operation?
		if (error) {
			*error = PA2MakeError(PowerAuthErrorCode_BiometryCancel, nil);
		}
		return nil;
	}
	
	// Compute signature for provided values and return result.
	PowerAuthCoreHTTPRequestDataSignature * signature = [_session signHttpRequestData:requestData keys:keys factor:factor];
	
	// Update keychain values after each successful calculations
	[self saveSessionState];
	
	if (signature == nil && error) {
		*error = PA2MakeError(PowerAuthErrorCode_SignatureError, nil);
	}
	return signature;
}


- (BOOL) verifyServerSignedData:(nonnull NSData*)data
					  signature:(nonnull NSString*)signature
					  masterKey:(BOOL)masterKey
{
	[self checkForValidSetup];
	
	PowerAuthCoreSignedData * signedData = [[PowerAuthCoreSignedData alloc] init];
	signedData.signingDataKey = masterKey ? PowerAuthCoreSigningDataKey_ECDSA_MasterServerKey : PowerAuthCoreSigningDataKey_ECDSA_PersonalizedKey;
	signedData.data = data;
	signedData.signatureBase64 = signature;

	return [_session verifyServerSignedData: signedData];
}


#pragma mark - Password

- (BOOL) unsafeChangePasswordFrom:(NSString*)oldPassword
							   to:(NSString*)newPassword
{
	BOOL result = [_session changeUserPassword:[PowerAuthCorePassword passwordWithString:oldPassword]
								   newPassword:[PowerAuthCorePassword passwordWithString:newPassword]];
	if (result) {
		[self saveSessionState];
	}
	return result;
}

- (id<PowerAuthOperationTask>) changePasswordFrom:(NSString*)oldPassword
											   to:(NSString*)newPassword
										 callback:(void(^)(NSError *error))callback
{
	return [self validatePasswordCorrect:oldPassword callback:^(NSError * _Nullable error) {
		if (!error) {
			// Let's change the password
			BOOL result = [_session changeUserPassword:[PowerAuthCorePassword passwordWithString:oldPassword]
										   newPassword:[PowerAuthCorePassword passwordWithString:newPassword]];
			if (result) {
				[self saveSessionState];
			} else {
				error = PA2MakeError(PowerAuthErrorCode_InvalidActivationState, nil);
			}
		}
		// Call back to application
		callback(error);
	}];
}

- (id<PowerAuthOperationTask>) validatePasswordCorrect:(NSString*)password callback:(void(^)(NSError * error))callback
{
	[self checkForValidSetup];
	return [_client postObject:[PA2ValidateSignatureRequest requestWithReason:@"VALIDATE_PASSWORD"]
							to:[PA2RestApiEndpoint validateSignature]
						  auth:[PowerAuthAuthentication possessionWithPassword:password]
					completion:^(PowerAuthRestApiResponseStatus status, id<PA2Decodable> response, NSError *error) {
						callback(error);
					}];
}

#pragma mark - Biometry

- (id<PowerAuthOperationTask>) addBiometryFactor:(NSString*)password
										callback:(void(^)(NSError *error))callback
{
	// Check if biometry can be used
	if (![PowerAuthKeychain canUseBiometricAuthentication]) {
		callback(PA2MakeError(PowerAuthErrorCode_BiometryNotAvailable, nil));
		return nil;
	}
	PowerAuthAuthentication * authentication = [PowerAuthAuthentication possessionWithPassword:password];
	return [self fetchEncryptedVaultUnlockKey:authentication reason:PA2VaultUnlockReason_ADD_BIOMETRY callback:^(NSString *encryptedEncryptionKey, NSError *error) {
		if (!error) {
			// Let's add the biometry key
			PowerAuthCoreSignatureUnlockKeys *keys = [[PowerAuthCoreSignatureUnlockKeys alloc] init];
			keys.possessionUnlockKey = [self deviceRelatedKey];
			keys.biometryUnlockKey = [PowerAuthCoreSession generateSignatureUnlockKey];

			BOOL result = [_session addBiometryFactor:encryptedEncryptionKey
												 keys:keys];
			if (result) {
				// Update keychain values after each successful calculations
				[self saveSessionState];
				[_biometryOnlyKeychain deleteDataForKey:_biometryKeyIdentifier];
				[_biometryOnlyKeychain addValue:keys.biometryUnlockKey forKey:_biometryKeyIdentifier access:_keychainConfiguration.biometricItemAccess];
			} else {
				error = PA2MakeError(PowerAuthErrorCode_InvalidActivationState, nil);
			}
		}
		// Call back to application
		callback(error);
	}];
}

- (BOOL) hasBiometryFactor
{
	[self checkForValidSetup];
	BOOL hasValue = [_biometryOnlyKeychain containsDataForKey:_biometryKeyIdentifier];
	hasValue = hasValue && [_session hasBiometryFactor];
	return hasValue;
}

- (BOOL) removeBiometryFactor
{
	[self checkForValidSetup];
	BOOL result = [_session removeBiometryFactor];
	if (result) {
		// Update keychain values after each successful calculations
		[self saveSessionState];
		[_biometryOnlyKeychain deleteDataForKey:_biometryKeyIdentifier];
	}
	return result;
}

- (void) authenticateUsingBiometryWithPrompt:(NSString *)prompt
									callback:(void(^)(PowerAuthAuthentication * authentication, NSError * error))callback
{
	[self checkForValidSetup];
	// Check if activation is present
	if (!_session.hasValidActivation) {
		callback(nil, PA2MakeError(PowerAuthErrorCode_MissingActivation, nil));
		return;
	}
	// Check if biometry can be used
	if (![PowerAuthKeychain canUseBiometricAuthentication]) {
		callback(nil, PA2MakeError(PowerAuthErrorCode_BiometryNotAvailable, nil));
		return;
	}
	
	// Delegate operation to the background thread, because access to keychain is blocking.
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		PowerAuthAuthentication * authentication;
		NSError * error;
		// Acquire key to unlock biometric factor
		BOOL userCancelled = NO;
		NSData * biometryKey = [self biometryRelatedKeyUserCancelled:&userCancelled prompt:prompt];
		if (biometryKey) {
			// The biometry key is available, so create a new PowerAuthAuthentication object preconfigured
			// with possession+biometry factors. The prompt is not needed for rhw future usage of this
			// authentication object, but it could be useful for debugging purposes.
			authentication = [PowerAuthAuthentication possessionWithBiometryWithPrompt:prompt];
			authentication.overridenBiometryKey = biometryKey;
			error = nil;
		} else {
			// Otherwise report an error depending on whether the operation was canceled by the user.
			authentication = nil;
			error = PA2MakeError(userCancelled ? PowerAuthErrorCode_BiometryCancel : PowerAuthErrorCode_BiometryFailed, nil);
		}
		// Report result back to the main thread
		dispatch_async(dispatch_get_main_queue(), ^{
			callback(authentication, error);
		});
	});

}

- (void) unlockBiometryKeysWithPrompt:(NSString*)prompt
							withBlock:(void(^)(NSDictionary<NSString*, NSData*> *keys, BOOL userCanceled))block
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__block OSStatus status;
		__block NSDictionary *keys;
		BOOL executed = [PowerAuthKeychain tryLockBiometryAndExecuteBlock:^{
			keys = [_biometryOnlyKeychain allItemsWithPrompt:prompt withStatus:&status];
		}];
		BOOL userCanceled = !executed || (status == errSecUserCanceled);
		block(keys, userCanceled);
	});
}

#pragma mark - Secure vault support


- (id<PowerAuthOperationTask>) fetchEncryptionKey:(PowerAuthAuthentication*)authentication
											index:(UInt64)index
										 callback:(void(^)(NSData *encryptionKey, NSError *error))callback
{
	return [self fetchEncryptedVaultUnlockKey:authentication reason:PA2VaultUnlockReason_FETCH_ENCRYPTION_KEY callback:^(NSString *encryptedEncryptionKey, NSError *error) {
		NSData * encryptionKey = nil;
		if (!error) {
			// Let's unlock encryption key
			PowerAuthCoreSignatureUnlockKeys *keys = [[PowerAuthCoreSignatureUnlockKeys alloc] init];
			keys.possessionUnlockKey = [self deviceRelatedKey];
			encryptionKey = [_session deriveCryptographicKeyFromVaultKey:encryptedEncryptionKey
																	keys:keys
																keyIndex:index];
			if (!encryptionKey) {
				error = PA2MakeError(PowerAuthErrorCode_Encryption, nil);
			}
		}
		// Call back to application
		callback(encryptionKey, error);
	}];
}

#pragma mark - Asymmetric signatures

- (id<PowerAuthOperationTask>) signDataWithDevicePrivateKey:(PowerAuthAuthentication*)authentication
													   data:(NSData*)data
												   callback:(void(^)(NSData *signature, NSError *error))callback
{
	return [self fetchEncryptedVaultUnlockKey:authentication reason:PA2VaultUnlockReason_SIGN_WITH_DEVICE_PRIVATE_KEY callback:^(NSString *encryptedEncryptionKey, NSError *error) {
		NSData *signature = nil;
		if (!error) {
			// Let's sign the data
			PowerAuthCoreSignatureUnlockKeys *keys = [[PowerAuthCoreSignatureUnlockKeys alloc] init];
			keys.possessionUnlockKey = [self deviceRelatedKey];
			signature = [_session signDataWithDevicePrivateKey:encryptedEncryptionKey
														  keys:keys
														  data:data];
			// Propagate error
			if (!signature) {
				error = PA2MakeError(PowerAuthErrorCode_Encryption, nil);
			}
		}
		// Call back to application
		callback(signature, error);
	}];
}

@end

#pragma mark - End-2-End Encryption

@implementation PowerAuthSDK (E2EE)

- (PowerAuthCoreEciesEncryptor*) eciesEncryptorForApplicationScope
{
	PA2PrivateEncryptorFactory * factory = [[PA2PrivateEncryptorFactory alloc] initWithSession:_session deviceRelatedKey:nil];
	return [factory encryptorWithId:PA2EncryptorId_GenericApplicationScope];
}

- (PowerAuthCoreEciesEncryptor*) eciesEncryptorForActivationScope
{
	if (![self hasValidActivation]) {
		PowerAuthLog(@"eciesEncryptorForActivation: There's no activation.");
		return nil;
	}
	NSData * deviceKey = [self deviceRelatedKey];
	PA2PrivateEncryptorFactory * factory = [[PA2PrivateEncryptorFactory alloc] initWithSession:_session deviceRelatedKey:deviceKey];
	return [factory encryptorWithId:PA2EncryptorId_GenericActivationScope];
}

@end


#pragma mark - Request synchronization

@implementation PowerAuthSDK (RequestSync)

- (nullable id<PowerAuthOperationTask>) executeBlockOnSerialQueue:(void(^ _Nonnull)(id<PowerAuthOperationTask> _Nonnull task))execute
{
	PA2AsyncOperation * operation = [[PA2AsyncOperation alloc] initWithReportQueue:dispatch_get_main_queue()];
	operation.executionBlock = ^id(PA2AsyncOperation *op) {
		execute(op);
		return nil;
	};
	return [self executeOperationOnSerialQueue:operation] ? operation : nil;
}

- (BOOL) executeOperationOnSerialQueue:(nonnull NSOperation *)operation
{
	if (![self hasValidActivation]) {
		PowerAuthLog(@"executeOperationOnSerialQueue: There's no activation.");
		return NO;
	}
	[_client.serialQueue addOperation:operation];
	return YES;
}

@end



#pragma mark - Recovery codes

@implementation PowerAuthSDK (RecoveryCode)

- (BOOL) hasActivationRecoveryData
{
	return _session.hasActivationRecoveryData;
}

- (nullable id<PowerAuthOperationTask>) activationRecoveryData:(nonnull PowerAuthAuthentication*)authentication
													  callback:(nonnull void(^)(PowerAuthActivationRecoveryData * _Nullable recoveryData, NSError * _Nullable error))callback
{
	if (!_session.hasActivationRecoveryData) {
		callback(nil, PA2MakeError(PowerAuthErrorCode_InvalidActivationState, @"Session has no recovery data available."));
		return nil;
	}
	return [self fetchEncryptedVaultUnlockKey:authentication reason:PA2VaultUnlockReason_RECOVERY_CODE callback:^(NSString *encryptedEncryptionKey, NSError *error) {
		PowerAuthActivationRecoveryData * activationRecovery = nil;
		if (!error) {
			// Let's sign the data
			PowerAuthCoreSignatureUnlockKeys *keys = [[PowerAuthCoreSignatureUnlockKeys alloc] init];
			keys.possessionUnlockKey = [self deviceRelatedKey];
			PowerAuthCoreRecoveryData * recoveryData = [_session activationRecoveryData:encryptedEncryptionKey keys:keys];
			// Propagate error
			if (recoveryData) {
				activationRecovery = [[PowerAuthActivationRecoveryData alloc] initWithRecoveryData:recoveryData];
			} else {
				error = PA2MakeError(PowerAuthErrorCode_Encryption, nil);
			}
		}
		// Call back to application
		callback(activationRecovery, error);
	}];
}

- (nullable id<PowerAuthOperationTask>) confirmRecoveryCode:(nonnull NSString*)recoveryCode
											 authentication:(nonnull PowerAuthAuthentication*)authentication
												   callback:(nonnull void(^)(BOOL alreadyConfirmed, NSError * _Nullable error))callback
{
	[self checkForValidSetup];
	
	// Check if there is an activation present
	if (!_session.hasValidActivation) {
		callback(NO, PA2MakeError(PowerAuthErrorCode_MissingActivation, nil));
		return nil;
	}
	
	// Validate recovery code
	PowerAuthActivationCode * otp = [PowerAuthActivationCodeUtil parseFromRecoveryCode:recoveryCode];
	if (!otp) {
		callback(NO, PA2MakeError(PowerAuthErrorCode_WrongParameter, @"Invalid recovery code."));
		return nil;
	}
	
	// Construct and post request
	PA2ConfirmRecoveryCodeRequest * request = [[PA2ConfirmRecoveryCodeRequest alloc] init];
	request.recoveryCode = otp.activationCode;
	return [_client postObject:request
							to:[PA2RestApiEndpoint confirmRecoveryCode]
						  auth:authentication
					completion:^(PowerAuthRestApiResponseStatus status, id<PA2Decodable> response, NSError *error) {
						BOOL alreadyConfirmed;
						if (status == PowerAuthRestApiResponseStatus_OK) {
							alreadyConfirmed = ((PA2ConfirmRecoveryCodeResponse*)response).alreadyConfirmed;
						} else {
							alreadyConfirmed = NO;
						}
						callback(alreadyConfirmed, error);
					}];
}


@end
