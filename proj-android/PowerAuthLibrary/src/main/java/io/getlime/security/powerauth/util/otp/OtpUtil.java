/*
 * Copyright 2017 Wultra s.r.o.
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

package io.getlime.security.powerauth.util.otp;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.getlime.security.powerauth.core.ActivationCode;
import io.getlime.security.powerauth.core.ActivationCodeUtil;

/**
 * The {@code OtpUtil} is now deprecated, please use {@link ActivationCodeUtil} as a replacement.
 */
@Deprecated
public class OtpUtil {

    /**
     * Parses an input activation code (which may or may not contain an optional signature) and
     * returns {@link ActivationCode} object filled with valid data. The method doesn't perform an auto-correction,
     * so the provided code must be valid.
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param activationCode string with an activation code.
     * @return {@link ActivationCode} object if code is valid, or null
     */
    public static @Nullable ActivationCode parseFromActivationCode(@NonNull String activationCode) {
        return ActivationCodeUtil.parseFromActivationCode(activationCode);
    }

    /**
     * Parses an input recovery code (which may or may not contain an optional "R:" prefix) and
     * returns {@link Otp} object filled with valid data. The method doesn't perform an auto-correction,
     * so the provided code must be valid.
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param recoveryCode string with a recovery code.
     * @return {@link Otp} object if code is valid, or null
     */
    public static @Nullable ActivationCode parseFromRecoveryCode(@NonNull String recoveryCode) {
        return ActivationCodeUtil.parseFromRecoveryCode(recoveryCode);
    }

    /**
     * Returns true if UTF codepoint is a valid character allowed in the activation or recovery code.
     * The method strictly checks whether the character is from [A-Z2-7] characters range.
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param utfCodepoint unicode code point to be validated.
     * @return true if provided character is allowed in the activation code.
     */
    public static boolean validateTypedCharacter(int utfCodepoint) {
        return ActivationCodeUtil.validateTypedCharacter(utfCodepoint);
    }

    /**
     * Validates an input UTF codepoint and returns 0 if it's not valid or cannot be corrected.
     * The non-zero returned value contains the same input character, or the corrected
     * one. You can use this method for validation &amp; auto-correction of just typed characters.
     * <p>
     * The function performs following auto-corrections:
     * <ul>
     * <li>lowercase characters are corrected to uppercase (e.g. 'a' will be corrected to 'A')</li>
     * <li>'0' is corrected to 'O' (zero to capital O)</li>
     * <li>'1' is corrected to 'I' (one to capital I)</li>
     * </ul>
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param utfCodepoint unicode code point to be validated.
     * @return 0 if character is not allowed, or non-null value with the same, or auto-corrected character.
     */
    public static int validateAndCorrectTypedCharacter(int utfCodepoint) {
        return ActivationCodeUtil.validateAndCorrectTypedCharacter(utfCodepoint);
    }

    /**
     * Returns true if provided string is a valid activation code. The input code must not contain
     * a signature part. You can use this method to validate a whole user-typed activation code
     * at once.
     *
     * Note that since protocol version V3, the activation code is protected with checksum, so the
     * code with right characters and right length can still be an invalid.
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param activationCode activation code without the signature part
     * @return true if code is valid
     */
    public static boolean validateActivationCode(@NonNull String activationCode) {
        return ActivationCodeUtil.validateActivationCode(activationCode);
    }

    /**
     * Returns true if provided string is a valid recovery code. You can use this method to validate
     * a whole user-typed recovery code at once. The input code may contain "R:" prefix, if code is
     * scanned from QR code.
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param recoveryCode recovery code which may, or may not contain "R:" prefix.
     * @return true if code is valid
     */
    public static boolean validateRecoveryCode(@NonNull String recoveryCode) {
        return ActivationCodeUtil.validateRecoveryCode(recoveryCode);
    }

    /**
     * Returns true if provided recovery PUK appears to be valid. You can use this method to validate
     * a whole user-typed recovery PUK at once. In current version, only 10 digits long string is
     * considered as a valid PUK.
     * <p>
     * Method is deprecated, please use {@link ActivationCodeUtil} class as a replacement.
     *
     * @param recoveryPuk recovery code which may, or may not contain "R:" prefix.
     * @return true if PUK appears to be a valid
     */
    public static boolean validateRecoveryPuk(@NonNull String recoveryPuk) {
        return ActivationCodeUtil.validateRecoveryPuk(recoveryPuk);
    }
}
