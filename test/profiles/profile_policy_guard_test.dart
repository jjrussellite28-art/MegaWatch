import 'package:megawatch/models/profiles/profile_policy.dart';
import 'package:megawatch/models/profiles/user_profile.dart';
import 'package:megawatch/services/profiles/profile_policy_guard.dart';
import 'package:megawatch/services/profiles/profile_runtime.dart';
import 'package:megawatch/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ProfilePolicyGuard.updateActiveProfile(null);
    ProfileRuntime.debugReset();
  });

  UserProfile profile(Set<ProfileFeature> enabled) {
    final now = DateTime.utc(2026, 8, 16);
    return UserProfile(
      id: 'p1',
      name: 'Person',
      role: UserProfileRole.member,
      policy: ProfilePolicy(enabled: enabled),
      authorizationRevision: 1,
      lifecycle: UserProfileLifecycle.active,
      visibleDataGeneration: 1,
      setupComplete: true,
      pinResetRequired: false,
      hasPin: false,
      lockOnResume: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('legacy mode allows everything (no profiles to gate by)', () {
    ProfileRuntime.initializeLegacy();
    expect(
      ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
      isTrue,
    );
  });

  test('committed mode with no snapshot fails CLOSED', () {
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'p1', dataGeneration: 1, sessionEpoch: 1),
    );
    // Briefly hiding a surface is recoverable; rendering a forbidden one
    // is not — absence of the mirror must deny, never allow.
    expect(
      ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
      isFalse,
    );
  });

  test('snapshot gates surfaces per the active profile', () {
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'p1', dataGeneration: 1, sessionEpoch: 1),
    );
    ProfilePolicyGuard.updateActiveProfile(
      profile(<ProfileFeature>{ProfileFeature.megawatchTv}),
    );
    expect(ProfilePolicyGuard.allowsSync(ProfileFeature.megawatchTv), isTrue);
    expect(ProfilePolicyGuard.allowsSync(ProfileFeature.iptv), isFalse);
    expect(
      ProfilePolicyGuard.allowsSync(ProfileFeature.keywordSearch),
      isFalse,
    );
  });
}
