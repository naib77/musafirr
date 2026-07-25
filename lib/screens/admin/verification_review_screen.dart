import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/image_upload_service.dart';
import '../../widgets/modern_banner.dart';

/// Screen for admin to review pending verification documents
class VerificationReviewScreen extends StatefulWidget {
  const VerificationReviewScreen({super.key});

  @override
  State<VerificationReviewScreen> createState() =>
      _VerificationReviewScreenState();
}

class _VerificationReviewScreenState extends State<VerificationReviewScreen> {
  List<Map<String, dynamic>> _pendingVerifications = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPendingVerifications();
  }

  Future<void> _loadPendingVerifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // Get users with pending verification status
      final response = await client
          .from('profiles')
          .select('''
            id,
            full_name,
            mobile,
            nid,
            id_document_type,
            verification_status,
            owner_documents(
              id,
              document_type,
              file_path,
              uploaded_at,
              verified_at
            )
          ''')
          .eq('verification_status', 'pending')
          .order('updated_at', ascending: false);

      final verifications = List<Map<String, dynamic>>.from(response);

      // The `documents` bucket is private — file_path is a storage path, not a
      // public URL. Resolve a short-lived signed URL for each document so the
      // previews below can actually load.
      final uploads = ImageUploadService.instance;
      for (final v in verifications) {
        final docs = List<Map<String, dynamic>>.from(v['owner_documents'] ?? []);
        for (final doc in docs) {
          final path = doc['file_path'] as String?;
          if (path != null && path.isNotEmpty) {
            doc['signed_url'] = await uploads.signedDocumentUrl(path);
          }
        }
        v['owner_documents'] = docs;
      }

      if (!mounted) return;
      setState(() {
        _pendingVerifications = verifications;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _approveVerification(String userId) async {
    try {
      final client = Supabase.instance.client;
      final adminId = client.auth.currentUser?.id;

      // Update all documents for this user as verified
      await client.from('owner_documents').update({
        'verified_at': DateTime.now().toUtc().toIso8601String(),
        'verified_by': adminId,
      }).eq('user_id', userId);

      // Update profile verification status
      await client.from('profiles').update({
        'verification_status': 'verified',
      }).eq('id', userId);

      if (mounted) {
        ModernBanner.showSuccess(context, 'Verification approved');
        _loadPendingVerifications();
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(context, 'Error: $e');
      }
    }
  }

  Future<void> _rejectVerification(String userId, String reason) async {
    try {
      final client = Supabase.instance.client;

      // Update profile verification status to rejected
      await client.from('profiles').update({
        'verification_status': 'rejected',
      }).eq('id', userId);

      // Add rejection reason to documents
      await client.from('owner_documents').update({
        'rejection_reason': reason,
      }).eq('user_id', userId);

      if (mounted) {
        ModernBanner.showWarning(context, 'Verification rejected');
        _loadPendingVerifications();
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(context, 'Error: $e');
      }
    }
  }

  void _showRejectDialog(String userId, String userName) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reject verification for $userName?'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection',
            hintText: 'e.g., Document not clear, Wrong document type',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _rejectVerification(userId, reasonController.text);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Verifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingVerifications,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loadPendingVerifications,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pendingVerifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No pending verifications',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'All verifications have been processed',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingVerifications.length,
      itemBuilder: (context, index) {
        final verification = _pendingVerifications[index];
        return _VerificationCard(
          userId: verification['id'],
          userName: verification['full_name'] ?? 'Unknown',
          phone: verification['mobile'] ?? '',
          idType: verification['id_document_type'] as String?,
          idNumber: verification['nid'] as String?,
          documents:
              List<Map<String, dynamic>>.from(verification['owner_documents'] ?? []),
          onApprove: () => _approveVerification(verification['id']),
          onReject: () =>
              _showRejectDialog(verification['id'], verification['full_name'] ?? 'User'),
        );
      },
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.userId,
    required this.userName,
    required this.phone,
    required this.idType,
    required this.idNumber,
    required this.documents,
    required this.onApprove,
    required this.onReject,
  });

  final String userId;
  final String userName;
  final String phone;
  final String? idType;
  final String? idNumber;
  final List<Map<String, dynamic>> documents;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  /// Friendly label for a stored `id_document_type` key.
  String _docTypeLabel(String? key) {
    switch (key) {
      case 'nid':
        return 'National ID (NID)';
      case 'passport':
        return 'Passport';
      case 'driving_license':
        return 'Driving License';
      case 'student_id':
        return 'Student / Admission';
      case 'office_id':
        return 'Office / Employee ID';
      default:
        return 'ID document';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final nidFront = documents.firstWhere(
      (d) => d['document_type'] == 'nid_front',
      orElse: () => {},
    );
    final nidBack = documents.firstWhere(
      (d) => d['document_type'] == 'nid_back',
      orElse: () => {},
    );
    final selfie = documents.firstWhere(
      (d) => d['document_type'] == 'selfie',
      orElse: () => {},
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info
          ListTile(
            leading: CircleAvatar(
              child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : 'U'),
            ),
            title: Text(userName),
            subtitle: Text(phone),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withAlpha(50),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Pending',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          ),
          const Divider(height: 1),

          // Documents
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Documents',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if ((idNumber ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_docTypeLabel(idType)} · No. $idNumber',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DocumentPreview(
                        label: 'ID Front',
                        url: nidFront['signed_url'] as String?,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DocumentPreview(
                        label: 'ID Back',
                        url: nidBack['signed_url'] as String?,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DocumentPreview(
                        label: 'Selfie',
                        url: selfie['signed_url'] as String?,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.label,
    required this.url,
  });

  final String label;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: url != null ? () => _showFullImage(context, url!) : null,
          child: Container(
            height: 100,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: url != null
                ? Image.network(
                    url!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
                  )
                : _buildPlaceholder(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Center(
      child: Icon(
        Icons.image_not_supported,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(label),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
