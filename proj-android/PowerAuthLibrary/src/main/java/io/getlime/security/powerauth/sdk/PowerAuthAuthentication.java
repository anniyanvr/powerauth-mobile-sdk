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

package io.getlime.security.powerauth.sdk;

import androidx.annotation.Nullable;

/**
 * Created by miroslavmichalec on 20/10/2016.
 */

public class PowerAuthAuthentication {

    /**
     * Indicates if a possession factor should be used.
     */
    public boolean usePossession;

    /**
     * Biometry key data, or nil if biometry factor should not be used.
     */
    public @Nullable byte[] useBiometry;

    /**
     * Password to be used for knowledge factor, or nil if knowledge factor should not be used.
     */
    public @Nullable String usePassword;

    /**
     * (optional) If 'usePossession' is set to YES, this value may specify possession key data. If no custom data is specified, default possession key is used.
     */
    public byte[] overridenPossessionKey;
}
