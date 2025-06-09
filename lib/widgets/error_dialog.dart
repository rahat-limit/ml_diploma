import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ErrorDialog extends StatelessWidget {
  final String title;
  final String error;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              error,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: error));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error copied to clipboard')),
                  );
                  Navigator.pop(context);
                },
              ),
              TextButton(
                child: const Text('Close'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void show(BuildContext context, String title, String? error) {
    if (error == null) return;

    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: title,
        error: error,
      ),
    );
  }
}
