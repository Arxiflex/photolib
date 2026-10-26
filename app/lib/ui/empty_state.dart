import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsets.all(AppTokens.of(context).md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: AppTokens.of(context).md,
        children: [
          Icon(icon, size: 64),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          ?action,
        ],
      ),
    ),
  );
}
