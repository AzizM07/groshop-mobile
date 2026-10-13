import 'package:flutter/material.dart';
import '../core/theme.dart';

const _ink = Color(0xFF0F1419);

class Accordion extends StatefulWidget {
  final String title;
  final Widget? trailing;
  final bool defaultOpen;
  final Widget child;
  const Accordion({super.key, required this.title, this.trailing, this.defaultOpen = false, required this.child});
  @override
  State<Accordion> createState() => _AccordionState();
}

class _AccordionState extends State<Accordion> {
  late bool _open = widget.defaultOpen;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(children: [
                Text(widget.title, style: AppTheme.body(size: 17, weight: FontWeight.w700, color: _ink)),
                if (widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!],
                const Spacer(),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.keyboard_arrow_down, size: 24, color: _ink),
                ),
              ]),
            ),
          ),
          if (_open)
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 18), child: widget.child),
        ],
      ),
    );
  }
}