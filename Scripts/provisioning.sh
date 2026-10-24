#!/bin/bash
# Shared by Scripts/build_dmg.sh and Scripts/build_pcc_dev.sh. Source it, then call
# apply_provisioning_profile.

# Reads a value from the decoded profile (empty if missing).
profile_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$PROFILE_PLIST" 2>/dev/null || true; }

# Decodes a provisioning profile into $PROFILE_PLIST so profile_value can read it.
decode_provisioning_profile() {
    local profile="$1" work_dir="$2"
    PROFILE_PLIST="$work_dir/profile.plist"
    security cms -D -i "$profile" > "$PROFILE_PLIST"
}

# apply_provisioning_profile <app bundle> <profile> <work dir>
#
# Embeds the profile in the app and writes an entitlements file (path in $ENTITLEMENTS) with the
# base entitlements plus each capability the profile grants:
#   - Private Cloud Compute: the Agent can answer with PCC (otherwise on-device only).
#   - iCloud key-value storage: reading positions and anchors sync between the user's Macs
#     (otherwise they stay on the Mac).
# Sets GRANTS_PCC and GRANTS_KVSTORE to 1 or 0. Fails if the profile is for another App ID.
apply_provisioning_profile() {
    local app="$1" profile="$2" work_dir="$3"
    decode_provisioning_profile "$profile" "$work_dir"
    local bundle_id team_id app_identifier
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
    team_id="$(profile_value Entitlements:com.apple.developer.team-identifier)"
    app_identifier="$(profile_value Entitlements:com.apple.application-identifier)"
    if [ "$app_identifier" != "$team_id.$bundle_id" ]; then
        echo "error: profile is for '$app_identifier', expected '$team_id.$bundle_id'" >&2
        return 1
    fi
    echo "Profile: $(profile_value Name), expires $(profile_value ExpirationDate)"
    cp "$profile" "$app/Contents/embedded.provisionprofile"

    ENTITLEMENTS="$work_dir/VectorPDF.entitlements"
    cp Resources/VectorPDF.entitlements "$ENTITLEMENTS"
    entitle() { /usr/libexec/PlistBuddy -c "Add :$1" "$ENTITLEMENTS"; }
    entitle "com.apple.application-identifier string $app_identifier"
    entitle "com.apple.developer.team-identifier string $team_id"
    GRANTS_PCC=0
    GRANTS_KVSTORE=0
    if [ "$(profile_value Entitlements:com.apple.developer.private-cloud-compute)" = "true" ]; then
        entitle "com.apple.developer.private-cloud-compute bool true"
        echo "Capability: Private Cloud Compute"
        GRANTS_PCC=1
    fi
    # The profile allows "TEAMID.*" or this app's own identifier; the app claims its own store.
    if [ -n "$(profile_value Entitlements:com.apple.developer.ubiquity-kvstore-identifier)" ]; then
        entitle "com.apple.developer.ubiquity-kvstore-identifier string $team_id.$bundle_id"
        echo "Capability: iCloud key-value storage"
        GRANTS_KVSTORE=1
    fi
}
