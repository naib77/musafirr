import 'package:flutter/material.dart';

import '../../screens/host/address_proof_screen.dart';
import '../../state/auth_state.dart';
import '../app_settings_service.dart';
import '../auth/auth_flow.dart';
import '../image_upload_service.dart';
import 'identity_gate.dart';

/// Everything that must be true before a host reaches the create-listing form.
///
/// This lived inline in `host_listings_screen._createListing`, and that is
/// precisely why it was not enforced: `CreateListingScreen` is pushed from
/// THREE places, and the other two — the host dashboard and the profile screen
/// — were bare `Navigator.push` calls with no checks at all. An unverified host
/// who opened the form from either of them could publish. Duplicating the
/// guard would have left the same trap for the fourth caller; a gate every
/// caller has to pass through does not.
///
/// Shaped like [IdentityGate.ensure] and [AuthFlow.ensureSignedIn]: false means
/// stop, and it has already told the host why.
class PublishGate {
  PublishGate._();

  /// True when this user may open the create-listing form.
  static Future<bool> ensure(
    BuildContext context,
    AuthStateNotifier authState,
  ) async {
    // Becoming a host requires an account first. Reaching the form signed-out
    // was possible the moment browsing went public, and the form would then
    // have written a listing owned by nobody.
    if (!await AuthFlow.ensureSignedIn(
      context,
      authState,
      reason: 'to list your place',
    )) {
      return false;
    }
    if (!context.mounted) return false;

    final userId = authState.currentUser!.id;

    // Identity gate: a host must have an admin-approved identity (ID document +
    // selfie, verified by an admin) before publishing a listing. Migration 114
    // enforces the same rule in the listings INSERT policy — before it, a
    // role='tenant' account with no verification at all had published three
    // real listings through the ungated entry points.
    if (!await IdentityGate.ensure(
      context,
      userId,
      reason: 'to publish a listing',
    )) {
      return false;
    }
    if (!context.mounted) return false;

    // When configured, a host must have submitted their address — the billed
    // copy AND the address in writing — before publishing a listing.
    //
    // SUBMITTING is the gate, not the verdict: an admin's physical visit takes
    // days, and a host who has done their part must not sit on an unpublishable
    // listing waiting for one. The "Address verified" badge is what waits for
    // the visit. A rejected submission is also allowed through — the host is
    // told why on the profile screen and can resubmit; blocking them here would
    // pull a live host's ability to list out from under them over a bad photo.
    if (!await AppSettingsService.instance.ensureRequireListingAddressProof()) {
      return true;
    }
    final address =
        await ImageUploadService.instance.addressVerification(userId);
    if (address.isSubmitted) return true;

    if (!context.mounted) return false;
    final uploaded = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressProofScreen(userId: userId),
      ),
    );
    // Host backed out without submitting — don't proceed to the form.
    return uploaded == true;
  }
}
