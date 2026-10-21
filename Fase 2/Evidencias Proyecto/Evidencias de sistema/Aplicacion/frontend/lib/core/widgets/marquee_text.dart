// lib/core/widgets/marquee_text.dart

import 'dart:async';
import 'package:flutter/material.dart';

/// Widget de desplazamiento horizontal continuo/cíclico (Efecto Marquesina/Marquee).
/// Permite visualizar textos largos que exceden el ancho disponible sin truncarlos.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration pauseDuration;
  final Duration scrollDuration;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.pauseDuration = const Duration(milliseconds: 1500),
    this.scrollDuration = const Duration(milliseconds: 3000),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  AnimationController? _animController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartScroll();
    });
  }

  void _checkAndStartScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      _animController = AnimationController(
        vsync: this,
        duration: widget.scrollDuration,
      );
      _animController!.addListener(() {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_animController!.value * maxScroll);
        }
      });
      _animController!.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _timer?.cancel();
          _timer = Timer(widget.pauseDuration, () {
            if (mounted && _animController != null) {
              _animController!.reverse();
            }
          });
        } else if (status == AnimationStatus.dismissed) {
          _timer?.cancel();
          _timer = Timer(widget.pauseDuration, () {
            if (mounted && _animController != null) {
              _animController!.forward();
            }
          });
        }
      });
      _timer?.cancel();
      _timer = Timer(widget.pauseDuration, () {
        if (mounted && _animController != null) {
          _animController!.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _animController?.dispose();
    _animController = null;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.hardEdge,
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
