import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io' show Platform;

class CustomTitleBar extends StatefulWidget {
  final String title;
  final Color? backgroundColor;

  const CustomTitleBar({
    super.key,
    this.title = 'Notepad+++',
    this.backgroundColor,
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      _checkMaximized();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _checkMaximized() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      bool isMaximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() {
          _isMaximized = isMaximized;
        });
      }
    }
  }

  @override
  void onWindowMaximize() {
    setState(() {
      _isMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      _isMaximized = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only show custom title bar on desktop
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.backgroundColor ?? Theme.of(context).colorScheme.primary;
    final titleBarColor = isDark
        ? Color.lerp(baseColor, Colors.black, 0.5) ?? baseColor
        : baseColor;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: titleBarColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Draggable area with title
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    // App icon
                    Container(
                      padding: const EdgeInsets.all(4),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Window control buttons
          _WindowButton(
            icon: Icons.remove,
            onPressed: () async {
              await windowManager.minimize();
            },
          ),
          _WindowButton(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            onPressed: () async {
              if (_isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowButton(
            icon: Icons.close,
            isClose: true,
            onPressed: () async {
              await windowManager.close();
            },
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isClose ? Colors.red : Colors.white.withValues(alpha: 0.1))
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
