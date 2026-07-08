import 'package:flutter/material.dart';

class DeliveryScreen extends StatefulWidget {
  final String packageId;

  const DeliveryScreen({super.key, required this.packageId});

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _receiverNameController = TextEditingController();
  final _receiverDocController = TextEditingController();
  final _otpController = TextEditingController();
  final _commentsController = TextEditingController();

  String? _selectedRelationship;
  bool _isWithinGeofence = true;
  bool _signatureCaptured = false;
  bool _photoIdCaptured = false;
  bool _photoPackageCaptured = false;

  final List<String> _relationships = [
    'Self',
    'Family Member',
    'Neighbor',
    'Coworker',
    'Building Staff',
    'Other',
  ];

  @override
  void dispose() {
    _receiverNameController.dispose();
    _receiverDocController.dispose();
    _otpController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Delivery'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPackageSummary(theme),
              const SizedBox(height: 24),
              _buildReceiverSection(theme),
              const SizedBox(height: 24),
              _buildSignatureSection(theme),
              const SizedBox(height: 24),
              _buildPhotoSection(theme),
              const SizedBox(height: 24),
              _buildGpsIndicator(theme),
              const SizedBox(height: 24),
              _buildOtpSection(theme),
              const SizedBox(height: 24),
              _buildCommentsSection(theme),
              const SizedBox(height: 32),
              _buildConfirmButton(theme),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackageSummary(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Package Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _summaryRow('Package ID', widget.packageId),
            _summaryRow('Status', 'Out for Delivery'),
            _summaryRow('Estimated Delivery', 'Today, 2:00 PM - 4:00 PM'),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildReceiverSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Receiver Information',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _receiverNameController,
          decoration: const InputDecoration(
            labelText: 'Receiver Name',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter receiver name';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _receiverDocController,
          decoration: const InputDecoration(
            labelText: 'Receiver Document',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter receiver document';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedRelationship,
          decoration: const InputDecoration(
            labelText: 'Relationship',
            prefixIcon: Icon(Icons.people_outline),
            border: OutlineInputBorder(),
          ),
          items: _relationships.map((rel) {
            return DropdownMenuItem(value: rel, child: Text(rel));
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedRelationship = value);
          },
          validator: (value) {
            if (value == null) {
              return 'Please select relationship';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSignatureSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signature',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            setState(() => _signatureCaptured = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Signature captured')),
            );
          },
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _signatureCaptured
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: _signatureCaptured ? 2 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _signatureCaptured ? Icons.check_circle : Icons.draw,
                  size: 40,
                  color: _signatureCaptured
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 8),
                Text(
                  _signatureCaptured ? 'Signature Captured' : 'Tap to sign',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: _signatureCaptured
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photo Evidence',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _photoButton(
                theme,
                label: 'Receiver ID',
                icon: Icons.camera_alt_outlined,
                captured: _photoIdCaptured,
                onTap: () => setState(() => _photoIdCaptured = true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _photoButton(
                theme,
                label: 'Package',
                icon: Icons.camera_alt_outlined,
                captured: _photoPackageCaptured,
                onTap: () => setState(() => _photoPackageCaptured = true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _photoButton(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required bool captured,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        captured ? Icons.check_circle : icon,
        color: captured ? Colors.green : null,
      ),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        side: captured
            ? const BorderSide(color: Colors.green, width: 2)
            : null,
      ),
    );
  }

  Widget _buildGpsIndicator(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isWithinGeofence
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isWithinGeofence ? Colors.green : Colors.red,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isWithinGeofence
                ? Icons.check_circle
                : Icons.location_off,
            color: _isWithinGeofence ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isWithinGeofence
                      ? 'GPS Verified'
                      : 'Outside Delivery Zone',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _isWithinGeofence ? Colors.green : Colors.red,
                  ),
                ),
                Text(
                  _isWithinGeofence
                      ? 'You are within the delivery geofence'
                      : 'Move closer to the delivery address',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Switch(
            value: _isWithinGeofence,
            onChanged: (val) => setState(() => _isWithinGeofence = val),
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildOtpSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OTP Verification',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            letterSpacing: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Enter 6-digit OTP',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          validator: (value) {
            if (value == null || value.length != 6) {
              return 'Please enter a valid 6-digit OTP';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildCommentsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _commentsController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Additional comments (optional)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton(ThemeData theme) {
    return FilledButton.icon(
      onPressed: () {
        if (_formKey.currentState!.validate()) {
          if (!_signatureCaptured) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please capture signature')),
            );
            return;
          }
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
              title: const Text('Delivery Confirmed'),
              content: const Text(
                'The package has been marked as delivered successfully.',
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      },
      icon: const Icon(Icons.check),
      label: const Text('Confirm Delivery'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
